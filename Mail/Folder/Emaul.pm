# -*-perl-*-
#
# Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: Emaul.pm,v 1.2 1996/07/16 04:47:18 kjj Exp $

package Mail::Folder::Emaul;
@ISA = qw(Mail::Folder);

=head1 NAME

Mail::Folder::Emaul - An Emaul folder interface for Mail::Folder.

I<B<WARNING: This code is in alpha release.> Expect the interface to
change.>

=head1 SYNOPSYS

C<use Mail::Folder::Emaul;>

=head1 DESCRIPTION

This module provides an interface to the B<emaul> folder mechanism.
It is currently intended to be used as an example of hooking a folder
interface into Mail::Folder.

B<Emaul>'s folder structure is styled after B<mh>.  It uses
directories for folders and numerically-named files for the individual
mail messages.  The current message for a particular folder is stored
in a file C<.current_msg> in the folder directory.

Many of B<mh>'s more useful features like sequences aren't
implemented, but what the hey...

=cut

use Mail::Folder;
use Mail::Internet;
use Carp;
use vars qw($VERSION);

$VERSION = "0.02";

=head1 METHODS

=head2 open($folder_name)

=item * Call the superclass C<open> method

=item * For every message file in the C<$folder_name> directory, add the
message_number to the object's list of messages.

=item * Load the contents of C<$folder_dir/.current_msg> into
C<$self-E<gt>{Current}>.

=cut

sub open {
  my $self = shift;
  my $file = shift;
  
  my($current_message, $message);
  local(*FILE);
  
  return(0) unless $self->SUPER::open($file);

  map($self->remember_message($_), get_folder_msgs($self->foldername()));
  $self->sort_message_list();
  
  if (open(FILE, $self->foldername() . "/.current_msg")) {
    $current_message = <FILE>;
    close(FILE);
    chomp($current_message);
    croak("non-numeric content in " . $self->foldername() . "/.current_msg")
      if ($current_message !~ /^\d+$/);
    $self->current_message($current_message);
  }
  return(1);
}

=head2 close()

Does nothing except call the C<close> method of the superclass.

=cut

sub close {
  my $self = shift;
  
  return($self->SUPER::close());
}

=head2 sync()

=item * Call the superclass C<sync> method

=item * For every pending delete, unlink that file in the folder
directory

=item * Clear out the 'pending delete' list.

=item * Scan the folder directory for message files that weren't
present the last time the folder was either C<open>ed or C<sync>ed.

=item * Add each new file found to the list of messages being slung
around in the Mail::Folder object.

=item * Update the contents of the folder's C<.current_msg> file.

=item * Return the number of new messages found.

=cut

sub sync {
  my $self = shift;
  
  my $current_message = $self->current_message();
  my $qty_new_messages = 0;
  my $msg;
  my @msgs;
  local(*FILE);
  
  return(-1) if ($self->SUPER::sync() == -1);

  foreach $msg (get_folder_msgs($self->foldername())) {
    if (!defined($self->{Messages}{$msg})) {
      $self->remember_message($msg);
      $qty_new_messages++;
    }
  }
  
  @msgs = map {$self->foldername() . "/$_"} $self->list_deletes();
  unlink(@msgs);
  map {$self->forget_message($_)} $self->list_deletes();
  $self->clear_deletes();
  $self->sort_message_list();
  
  open(FILE, ">" . $self->foldername() . "/.current_msg") ||
    croak("can't write " . $self->foldername() . "/.current_msg: $!");
  print(FILE "$current_message\n");
  close(FILE);
  
  return($qty_new_messages);
}

=head2 pack()

Calls the superclass C<pack> method.

Renames the message files in the folder so that there are no
gaps in the numbering sequence.

Old deleted message files (ones that start with C<,>) are also renamed
as necessary.

It also tweaks current_message accordingly.

It will abandon the operation and return C<0> if a C<rename> fails,
otherwise it returns C<1>.

Please note that C<pack> acts on the real folder.

=cut

sub pack {
  my $self = shift;
  
  my($newmsg) = 0;
  my($folder) = $self->foldername();
  my($current_message) = $self->current_message();
  my $msg;
  
  return(0) unless $self->SUPER::pack();
  
  foreach $msg ($self->message_list()) {
    $newmsg++;
    if ($msg > $newmsg) {
      return(0) if (!rename("$folder/$msg", "$folder/$newmsg"));
      if (-e "$folder/,$msg") {
	return(0) if (!rename("$folder/,$msg", "$folder/,$newmsg"));
      }
      $self->current_message($newmsg) if ($msg == $current_message);
      $self->remember_message($newmsg);
      $self->cache_header($newmsg, $self->{Headers}{$msg});
      $self->forget_message($msg);
    }
  }
  $self->sort_message_list();
  return(1);
}

=head2 get_message($msg_number)

Calls the superclass C<get_message> method.

Retrieves the given mail message file into a B<Mail::Internet> object
reference and returns the reference.

=cut

sub get_message {
  my $self = shift;
  my $key = shift;
  
  my $message;
  local(*FILE);
  
  return(undef) unless $self->SUPER::get_message($key);

  if (defined($self->{Messages}{$key})) {
    open(FILE, $self->foldername() . "/$key") ||
      croak("can't open " . $self->foldername() . "/$key: $!");
    $message = Mail::Internet->new(<FILE>);
    close(FILE);
    return($message);
  }
  return(undef);
}

=head2 get_header($msg_number)

The C<$self-E<gt>{Headers}> associative array in a B<Mail::Folder>
object is used to hold B<Mail::Internet> object references containing
the headers of the mail messages in the folder.  For performance
reasons, the header references aren't retrieved immediately by the
C<open> method, they are retrieved by C<get_header> as needed.

If the particular header has never been retrieved then C<get_header>
loads the header of the given mail message into
C<$self-E<gt>{Headers}{$msg_number}> and returns the object reference

If the header for the given mail message has already been retrieved in
a prior call to C<get_header>, then the cached entry is returned.

It also calls the superclass C<get_header> method.

=cut

sub get_header {
  my $self = shift;
  my $key = shift;
  
  my $header;
  local(*FILE);

  return($self->{Headers}{$key}) if ($self->{Headers}{$key});
  
  return(undef) unless $self->SUPER::get_header($key);

  if (open(FILE, $self->foldername() . "/$key")) {
    $header = Mail::Internet->new();
    $header->read_header(\*FILE);
    close(FILE);
    $self->cache_header($key, $header);
    return($header);
  }
  return(undef);
}

=head2 append_message($message_ref)

=item * Call the superclass C<append_message> method.

=item * Retrieve the highest message number in the folder

=item * increment it

=item * Create a new mail message file in the folder with the
contents of C<$message_ref>.

Please note that, contrary to the documentation for B<Mail::Folder>,
actually updates the real folder, rather than queueing it up for a
subsequent sync.  The C<dup> and C<refile> methods are also
affected. This will be fixed soon.

=cut

sub append_message {
  my $self = shift;
  my $message_ref = shift;
  
  my($message_num) = $self->last_message();
  local(*FILE);
  
  return(0) unless $self->SUPER::append_message($message_ref);

  $message_num++;
  write_message($self->foldername(), $message_num, $message_ref);
  $self->remember_message($message_num);
  $self->cache_header($message_num, $message_ref->header());
  $self->sort_message_list();
  return(1);
}

=head2 update_message($msg_number, $message_ref)

=item * Call the superclass C<update_message> method.

=item * Replaces the contents of the given mail file with the contents of
C<$message_ref>.

Please note that, contrary to the documentation for B<Mail::Folder>,
actually updates the real folder, rather than queueing it up for a
subsequent sync.  This will be fixed soon.

=cut

sub update_message {
  my $self = shift;
  my $key = shift;
  my $message_ref = shift;
  
  local(*FILE);
  
  return(0) unless $self->SUPER::update_message($key, $message_ref);

  write_message($self->foldername(), $key, $message_ref);
  
  return(1);
}
###############################################################################
sub get_folder_msgs {
  my $folder_dir = shift;
  
  my @files;
  local(*DIR);
  
  opendir(DIR, $folder_dir) || croak("can't open $folder_dir: $!");
  @files = grep(/^\d+$/, readdir(DIR));
  closedir(DIR);
  
  return(sort {$a <=> $b} @files);
}

sub write_message {
  my $folder_dir = shift;
  my $key = shift;
  my $message_ref = shift;
  
  local(*FILE);
  
  rename("$folder_dir/$key", "$folder_dir/,$key")
    if (-e "$folder_dir/$key");
  
  open(FILE, ">$folder_dir/$key") ||
    croak("can't write $folder_dir/$key: $!");
  chmod(0600, "$folder_dir/.current_msg") ||
    croak("can't chmod $folder_dir/.current_msg: $!");
  $message_ref->print(\*FILE);
  close(FILE);
  
  return(1);
}

=head1 AUTHOR

Kevin Johnson E<lt>F<kjj@primenet.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
