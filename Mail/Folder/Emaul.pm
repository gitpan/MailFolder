# -*-perl-*-
#
# Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: Emaul.pm,v 1.3 1996/08/03 17:32:21 kjj Exp $

package Mail::Folder::Emaul;
@ISA = qw(Mail::Folder);
use Mail::Folder;

Mail::Folder::register_folder_type(Mail::Folder::Emaul, 'emaul');

=head1 NAME

Mail::Folder::Emaul - An Emaul folder interface for Mail::Folder.

B<WARNING: This code is in alpha release. Expect the interface to
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

=cut

use Mail::Folder;
use Mail::Internet;
use Carp;
use vars qw($VERSION);

$VERSION = "0.03";

=head1 METHODS

=head2 open($folder_name)

Populates the C<Mail::Folder> object with information about the
folder.

=over 2

=item * Call the superclass C<open> method

=item * For every message file in the C<$folder_name> directory, add the
message_number to the object's list of messages.

=item * Load the contents of C<$folder_dir/.current_msg> into
C<$self-E<gt>{Current}>.

=back

=cut

sub open {
  my $self = shift;
  my $foldername = shift;

  my($current_message, $message);
  local(*FILE);
  
  return(0) unless $self->SUPER::open($foldername);

  $self->set_readonly if (! -w $foldername);

  map($self->remember_message($_), get_folder_msgs($foldername));
  $self->sort_message_list;

  $self->current_message(load_current_msg($foldername));
  $self->load_message_labels;

  return(1);
}

=head2 close

Does nothing except call the C<close> method of the superclass.

=cut

sub close { return($_[0]->SUPER::close); }

=head2 sync

Flushes any pending changes out to the original folder.

=over 2

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

=back

=cut

sub sync {
  my $self = shift;
  
  my $current_message = $self->current_message;
  my $qty_new_messages = 0;
  my @deletes = $self->select_label('delete');
  my $foldername = $self->foldername;
  
  return(-1) if ($self->SUPER::sync == -1);

  for (get_folder_msgs($foldername)) {
    if (!defined($self->{Messages}{$_})) {
      $self->remember_message($_);
      $qty_new_messages++;
    }
  }

  if (!$self->is_readonly && @deletes) {
    unlink(map { "$foldername/$_" } @deletes);
    map {$self->forget_message($_)} @deletes;
    $self->clear_label('delete');
  }

  $self->sort_message_list;

  if (!$self->is_readonly) {
    store_current_msg($foldername, $current_message);
    $self->store_message_labels($foldername);
  }
  
  return($qty_new_messages);
}

=head2 pack

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
  my($folder) = $self->foldername;
  my($current_message) = $self->current_message;
  
  return(0) if (!$self->SUPER::pack || $self->is_readonly);

  for ($self->message_list) {
    $newmsg++;
    if ($_ > $newmsg) {
      return(0) if (!rename("$folder/$_", "$folder/$newmsg") ||
		    (-e "$folder/,$_" &&
		     !rename("$folder/,$_", "$folder/,$newmsg")));
      $self->current_message($newmsg) if ($_ == $current_message);
      $self->remember_message($newmsg);
      $self->cache_header($newmsg, $self->{Messages}{$_}{Header});
      $self->forget_message($_);
    }
  }
  $self->sort_message_list;
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
    open(FILE, $self->foldername . "/$key") ||
      croak("can't open " . $self->foldername . "/$key: $!");
    $message = new Mail::Internet(<FILE>);
    close(FILE);
    return($message);
  }
  return(undef);
}

=head2 get_header($msg_number)

If the particular header has never been retrieved then C<get_header>
loads the header of the given mail message into a member of
C<$self-E<gt>{Messages}{$msg_number}> and returns the object reference

If the header for the given mail message has already been retrieved in
a prior call to C<get_header>, then the cached entry is returned.

It also calls the superclass C<get_header> method.

=cut

sub get_header {
  my $self = shift;
  my $key = shift;
  
  my $header;
  local(*FILE);

  return($self->{Messages}{$key}{Header}) if ($self->{Messages}{$key}{Header});
  
  return(undef) unless $self->SUPER::get_header($key);

  if (open(FILE, $self->foldername . "/$key")) {
    $header = new Mail::Internet;
    $header->read_header(\*FILE);
    close(FILE);
    $self->cache_header($key, $header);
    return($header);
  }
  return(undef);
}

=head2 append_message($message_ref)

Appends the contents of the mail message contained C<$message_ref> to
the the folder.

=over 2

=item * Call the superclass C<append_message> method.

=item * Retrieve the highest message number in the folder

=item * increment it

=item * Create a new mail message file in the folder with the
contents of C<$message_ref>.

=back

Please note that, contrary to other documentation for B<Mail::Folder>,
the Emaul C<append_message> method actually updates the real folder,
rather than queueing it up for a subsequent sync.  The C<dup> and
C<refile> methods are also affected. This will be fixed soon.

=cut

sub append_message {
  my $self = shift;
  my $message_ref = shift;
  
  my($message_num) = $self->last_message;
  local(*FILE);
  
  return(0) unless $self->SUPER::append_message($message_ref);

  $message_num++;
  write_message($self->foldername, $message_num, $message_ref);
  $self->remember_message($message_num);
  $self->cache_header($message_num, $message_ref->header);
  $self->sort_message_list;
  return(1);
}

=head2 update_message($msg_number, $message_ref)

Replaces the message pointed to by C<$msg_number> with the contents of
the C<Mail::Internet> object reference C<$message_ref>.

=over 2

=item * Call the superclass C<update_message> method.

=item * Replaces the contents of the given mail file with the contents of
C<$message_ref>.

=back

Please note that, contrary to other documentation for B<Mail::Folder>,
the Emaul C<update_message> method actually updates the real folder,
rather than queueing it up for a subsequent sync.  This will be fixed
soon.

=cut

sub update_message {
  my $self = shift;
  my $key = shift;
  my $message_ref = shift;
  
  local(*FILE);
  
  return(0) unless $self->SUPER::update_message($key, $message_ref);

  write_message($self->foldername, $key, $message_ref);
  
  return(1);
}

=head2 create($foldername)

Creates a new folder named C<$foldername>.  Returns C<0> if the folder
already exists, otherwise returns of the folder creation was
successful.

=cut

sub create {
  my $self = shift;
  my $foldername = shift;

  return(0) if (-e $foldername);

  mkdir($foldername, 0700) || croak("can't create $foldername: $!\n");
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

  return(@files);
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
  chmod(0600, "$folder_dir/$key") ||
    croak("can't chmod $folder_dir/$key: $!");
  $message_ref->print(\*FILE);
  close(FILE);
  
  return(1);
}

sub load_current_msg {
  my $foldername = shift;
  my $current_msg = 0;
  local(*FILE);
  
  if (open(FILE, "$foldername/.current_msg")) {
    $current_msg = <FILE>;
    close(FILE);
    chomp($current_msg);
    croak("non-numeric content in $foldername/.current_msg")
      if ($current_msg !~ /^\d+$/);
  }
  return($current_msg);
}

sub store_current_msg {
  my $foldername = shift;
  my $current_msg = shift;
  
  local(*FILE);

  open(FILE, ">$foldername/.current_msg") ||
    croak("can't write $foldername/.current_msg: $!");
  print(FILE "$current_msg\n");
  close(FILE);
}

sub store_message_labels {
  my $self = shift;
  my @alllabels = $self->list_all_labels;
  my @labels;
  local(*FILE);

  if (@alllabels) {
    open(FILE, ">" . $self->foldername . "/.msg_labels") ||
      croak("can't create " . $self->foldername . "/.msg_labels: $!\n");
    for (@alllabels) {
      @labels = $self->select_label($_);
      print(FILE "$_: ", collapse_select_list(@labels), "\n");
    }
    close(FILE);
  }
}

sub collapse_select_list {
  my @list = @_;
  my @commalist;
  my $low = $list[0];
  my $high = $low;

  for (@list) {
    if ($_ > ($low + 1)) {
      push(@commalist, ($low != $high) ? "$low-$high" : $low);
      $low = $_;
    }
    $high = $_;
  }
  push(@commalist, ($low != $high) ? "$low-$high" : $low);
  return(join(',', @commalist));
}

sub load_message_labels {
  my $self = shift;

  my %labels;
  my($label, $value);
  my($commachunk, $low, $high);
  local(*FILE);

  if (open(FILE, $self->foldername . "/.msg_labels")) {
    while (<FILE>) {
      chomp;
      next if (/^\s*$/);
      next if (/^\s*\#/);
      ($label, $value) = split(/\s*:\s*/, $_, 2);
      $labels{$label} = $value;
      foreach $commachunk (split(',', $value)) {
	if ($commachunk =~ /-/) {
	  ($low, $high) = split(/-/, $commachunk, 2);
	} else { $low = $high = $commachunk; }
	($low <= $high) || croak("bad message spec: $low > $high: $value\n");
	(($low =~ /^\d+$/) && ($high =~ /^\d+$/)) ||
	  croak("bad message spec: $value\n");
	for (; $low <= $high; $low++) {
	  ($self->add_label($low, $label))
	    if (defined($self->{Messages}{$low}));
	}
      }
    }
    close(FILE);
  }
}

=head1 AUTHOR

Kevin Johnson E<lt>F<kjj@primenet.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
