# -*-perl-*-
#
# Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.

package Mail::Folder::Emaul;
@ISA = qw(Mail::Folder);

=head1 NAME

Mail::Folder::Emaul - An Emaul folder interface for Mail::Folder.

I<B<WARNING: This code is in alpha release.>
Expect the interface to change.>

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

$VERSION = "0.01";

=head1 METHODS

=head2 open($folder_name)

=item * Call the superclass B<open> method

=item * For every message file in the $folder_name directory, add the
message_number to the object's list of messages.

=item * Load the contents of C<$folder_dir/.current_msg> into
C<$self-E<gt>{Current}>.

=cut

sub open {
  my $self = shift;
  my $file = shift;
  
  my($msg, $current_message, $message);
  local(*FILE);
  
  return(0) unless $self->SUPER::open($file);
  
  foreach $msg (get_folder_msgs($self->foldername())) {
    $self->remember_message($msg, 0);
  }
  
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

Does nothing except call the B<close> method of the superclass.

=cut

sub close {
  my $self = shift;
  
  return($self->SUPER::close());
}

=head2 sync()

=item * Call the superclass B<sync> method

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
  local(*FILE);
  
  return(-1) if ($self->SUPER::sync() == -1);

  foreach $msg ($self->list_deletes()) {
    unlink($self->foldername() . "/$msg");
  }
  $self->clear_deletes();
  
  foreach $msg (get_folder_msgs($self->foldername())) {
    if (!defined($self->{Messages}{$msg})) {
      $self->remember_message($msg, 0);
      $qty_new_messages++;
    }
  }
  
  open(FILE, ">" . $self->foldername() . "/.current_msg") ||
    croak("can't write " . $self->foldername() . "/.current_msg: $!");
  print(FILE "$current_message\n");
  close(FILE);
  
  return($qty_new_messages);
}

=head2 pack()

Calls the superclass B<pack> method.

Renames the message files in the folder so that there are no
gaps in the numbering sequence.

Old deleted message files (ones that start with C<,>) are also renamed
as necessary.

It also tweaks current_message accordingly.

It will abandon the operation and return C<0> if a C<rename> fails,
otherwise it returns C<1>.

=cut

sub pack {
  my $self = shift;
  
  my(@msgs, $msg);
  my($newmsg) = 0;
  my($folder) = $self->foldername();
  my($current_message) = $self->current_message();
  
  return(0) unless $self->SUPER::pack();
  
  @msgs = $self->message_list();
  foreach $msg (@msgs) {
    $newmsg++;
    if ($msg > $newmsg) {
      return(0) if (!rename("$folder/$msg", "$folder/$newmsg"));
      if (-e "$folder/,$msg") {
	return(0) if (!rename("$folder/,$msg", "$folder/,$newmsg"));
      }
      $self->current_message($newmsg) if ($msg == $current_message);
      $self->remember_message($newmsg, $self->{Messages}{$msg});
      $self->forget_message($msg);
    }
  }
  return(1);
}

=head2 get_message($msg_number)

Calls the superclass B<get_message> method.

Retrieves the given mail message file into a B<Mail::Internet> object
reference and returns the reference.

=cut

sub get_message {
  my $self = shift;
  my $key = shift;
  
  my $message;
  local(*FILE);
  
  return(undef) unless $self->SUPER::get_message();

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

The C<$self-E<gt>{Messages}> associative array in a B<Mail::Folder> object
is used to hold B<Mail::Internet> object references containing the
headers of the mail messages in the folder.  For performance reasons,
the header references aren't populated immediately in the B<open>
method, they are retrieved by B<get_header> as needed.

If the particular header has never been retrieved then B<get_header>
loads the header of the given mail message into
C<$self-E<gt>{Messages}{$msg_number}> and returns the object reference

If the header for the given mail messages has already been retrieved
in a prior call to B<get_header>, then it is returned.

It also calls the superclass B<get_header> method.

=cut

sub get_header {
  my $self = shift;
  my $key = shift;
  
  my $header;
  local(*FILE);

  return($self->{Messages}{$key}) if ($self->{Messages}{$key});
  
  return(undef) unless $self->SUPER::get_header();

  if (open(FILE, $self->foldername() . "/$key")) {
    $header = Mail::Internet->new();
    $header->read_header(\*FILE);
    close(FILE);
    $self->remember_message($key, $header);
    return($header);
  }
  return(undef);
}

=head2 append_message($message_ref)

=item * Call the superclass B<append_message> method

=item * Retrieve the highest message number in the folder

=item * increment it

=item * Create a new mail message file in the folder with the
contents of C<$message_ref>.

=cut

sub append_message {
  my $self = shift;
  my $message_ref = shift;
  
  my($message_num);
  local(*FILE);
  
  return(0) unless $self->SUPER::append_message();

  $message_num = $self->last_message();
  $message_num++;
  write_message($self->foldername(), $message_num, $message_ref);
  $self->remember_message($message_num, $message_ref->header());
  return(1);
}

=head2 update_message($msg_number, $message_ref)

=item * Call the superclass B<update_message> method.

=item * Replaces the contents of the given mail file with the contents of
C<$message_ref>.

=cut

sub update_message {
  my $self = shift;
  my $key = shift;
  my $message_ref = shift;
  
  local(*FILE);
  
  return(0) if (!defined($self->{Messages}{$key}));
  
  return(0) unless $self->SUPER::update_message();

  write_message($self->foldername(), $key, $message_ref);
  
  return(1);
}
###############################################################################
sub get_folder_msgs {
  my $folder_dir = shift;
  
  my(@files, $file);
  local(*DIR);
  
  opendir(DIR, $folder_dir) || croak("can't open $folder_dir: $!");
  foreach $file (readdir(DIR)) {
    next if ($file !~ /^\d+$/);
    push(@files, $file);
  }
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
