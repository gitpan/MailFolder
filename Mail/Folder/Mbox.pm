# -*-perl-*-
#
# Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: Mbox.pm,v 1.2 1996/08/03 17:32:21 kjj Exp $

package Mail::Folder::Mbox;
@ISA = qw(Mail::Folder);

=head1 NAME

Mail::Folder::Mbox - A Unix mbox interface for Mail::Folder.

B<WARNING: This code is in alpha release. Expect the interface to
change.>

=head1 SYNOPSYS

C<use Mail::Folder::Mbox;>

=head1 DESCRIPTION

This module provides an interface to unix B<mbox> folders.

The B<mbox> folder format is the standard monolithic folder structure
prevalent on Unix.  A single folder is contained within a single file.
Each message starts with a line matching C</^From />.

The folder architecture doesn't provide any persistantly stored
current message variable, so the current message in this folder
interface defaults to C<1> and is not retained between C<open>s of a
folder.

C<Mbox> needs the following module packages:

=over 2

=item C<TimeDate>

=item C<File-Tools>

=item C<File-BasicFLock>

=back

=cut

use Mail::Folder;
use Mail::Internet;
use Mail::Address;
use Carp;
use File::Tools;
use Date::Format;
use Date::Parse;
use File::BasicFlock;

use vars qw($VERSION);

$VERSION = "0.03";

$folder_id = 0;			# used to generate a unique id per open folder

Mail::Folder::register_folder_type(Mail::Folder::Mbox, 'mbox');

=head1 METHODS

=head2 init

Initializes various items specific to B<Mbox>.

=over 2

=item * Determines an appropriate temporary directory.

=item * Bumps a sequence number used for unique temporary filenames.

=item * Initializes C<$self-E<gt>{WorkingFile}> to the name of a file that
will be used to hold the temporary working of the folder.

=item * Initializes C<$self-E<gt>{MsgFilePrefix}> to a string that will be
used to create temporary filenames when extracting messages from the
folder.

=back

=cut

sub init {
  my $self = shift;

  my $tmpdir = $ENV{TMPDIR} ? $ENV{TMPDIR} : "/tmp";
  $folder_id++;

  $self->{WorkingFile} = "$tmpdir/mbox.$folder_id.$$";
  $self->{MsgFilePrefix} = "$tmpdir/msg.$folder_id.$$";

  return(1);
}

=head2 open($folder_name)

=over 2

=item * Call the superclass C<open> method.

=item * Lock the folder.

=item * Copy the folder to a temporary location as a working copy.

=item * Unlock the folder.

=item * For every message in the folder, add the message_number to the
object's list of messages.

=back

=cut

sub open {
  my $self = shift;
  my $foldername = shift;

  my $message_number = 0;
  my $file_pos = 0;
  local(*FILE);

  return(0) unless $self->SUPER::open($foldername);

  valid_mbox($foldername) || croak("$foldername isn't an mbox file\n");

  $self->set_readonly if (! -w $foldername);

  lock_folder($foldername) || return(0);

  if (!copy($foldername, $self->{WorkingFile})) {
    unlock_folder($foldername);
    croak("can't create $self->{WorkingFile}: $!\n");
  }

  if (!unlock_folder($foldername)) {
    unlink($self->{WorkingFile});
    return(0);
  }

  $self->remember_mbox_points($self->{WorkingFile}, 0);

  $self->sort_message_list;
  $self->current_message(1);

  return(1);
}

sub valid_mbox {
  my $filename = shift;
  local(*FILE);

  return(1) if (-z $filename);
  open(FILE, $filename) || croak("can't open $filename: $!\n");
  $_ = <FILE>;
  close(FILE);
  return(/^From /);
}

sub remember_mbox_points {
  my $self = shift;
  my $filename = shift;
  my $first_message_number = shift;

  my $message_number = $first_message_number;
  my $seek_pos = 0;
  my $file_pos = 0;
  my $last_was_blank = 0;

  $seek_pos = $self->{Messages}{$message_number}{MboxFilePos}[1]
    if ($message_number);

  open(FILE, $filename) || croak("can't open $filename: $!\n");
  seek(FILE, $seek_pos, 0) ||
    croak("can't seek to $seek_pos in $filename: $!\n");
  while (<FILE>) {
    if (/^From /) {
      $message_number++;
      $self->remember_message($message_number);
      $self->{Messages}{$message_number}{MboxFilePos} = [$file_pos, 0];
      if ($message_number > 1) {
	$message_number--;
	$self->{Messages}{$message_number}{MboxFilePos}[1] =
	  $file_pos - ($last_was_blank ? 2 : 1);
	$message_number++;
      }
    }
    $file_pos = tell(FILE);
    $last_was_blank = /^$/ ? 1 : 0;
  }
  if ($message_number) {
    $self->{Messages}{$message_number}{MboxFilePos}[1] =
      $file_pos - ($last_was_blank ? 2 : 1);
  }
  close(FILE);

  return($message_number - $first_message_number);
}

=head2 close

Deletes the working copy of the folder and calls the superclass
C<close> method.

=cut

sub close {
  my $self = shift;

  unlink($self->{WorkingFile});
  return($self->SUPER::close);
}

=head2 sync

=over 2

=item * Call the superclass C<sync> method

=item * Lock the folder

=item * Append new messages to the working copy that have been
appended to the folder since the last time the folder was either
C<open>ed or C<sync>ed.

=item * Create a new copy of the folder and populate it with the
messages in the working copy that aren't flagged for deletion.

=item * Move the original folder to a temp location

=item * Move the new folder into place

=item * Delete the old original folder

=item * Unlock the folder

=back

=cut

sub sync {
  my $self = shift;

  my $last_message_number;
  my $qty_new_messages = 0;
  my $i = 0;
  my @statary;
  my $folder = $self->foldername;
  my $tmpfolder = "$folder.$$";
  my $file_pos;

  local(*INFILE);
  local(*OUTFILE);

  return(-1) if ($self->SUPER::sync == -1);

  open(OUTFILE, ">>$self->{WorkingFile}") ||
    croak("can't append to $self->{WorkingFile}: $!\n");

  chmod(0600, $self->{WorkingFile}) ||
    croak("can't chmod $self->{WorkingFile}: $!\n");

  $last_message_number = $self->last_message;

  return(-1) if (!lock_folder($folder));

  $qty_new_messages = $self->remember_mbox_points($folder,
						  $last_message_number);

  if (!open(INFILE, $folder)) {
    unlock_folder($folder);
    croak("can't open $folder: $!\n");
  }

  $file_pos = tell(OUTFILE);
  seek(INFILE, $file_pos, 0) ||
    croak("can't seek to $file_pos in $folder: $!\n");
  while (<INFILE>) {
    print(OUTFILE $_);
  }

  close(OUTFILE);
  $self->sort_message_list;

  # Create a new copy of the folder and populate it with the messages
  # in the working copy that aren't flagged for deletion.

  if (!$self->is_readonly) {
    if (!open(OUTFILE, ">$tmpfolder")) {
      unlock_folder($folder);
      croak("can't create $tmpfolder: $!\n");
    }
    if (!open(INFILE, $self->{WorkingFile})) {
      unlock_folder($folder);
      croak("can't open $self->{WorkingFile}: $!\n");
    }
    @statary = stat(INFILE);
    if (!chmod(($statary[2] & 0777), $tmpfolder)) {
      unlink($tmpfolder);
      croak("can't chmod $tmpfolder: $!\n");
    }
    
    $i = 0;
    while (<INFILE>) {
      $i++ if (/^From /);
      print(OUTFILE $_) if (!$self->label_exists($i, 'delete'));
    }
    close(INFILE);
    close(OUTFILE);
    map {$self->forget_message($_)} $self->select_label('delete');
    $self->clear_label('delete');
    $self->sort_message_list;
    
    # Move the original folder to a temp location
    
    if (!rename($folder, "$folder.old")) {
      unlock_folder($folder);
      croak("can't move $folder out of the way: $!\n");
    }
    
    # Move the new folder into place
    
    if (!rename($tmpfolder, $folder)) {
      unlock_folder($folder);
      croak("gack! can't rename $folder.old to $folder: $!\n")
	if (!rename("$folder.old", $folder));
      croak("can't move $folder to $folder.old: $!\n");
    }
    
    # Delete the old original folder
    
    if (!unlink("$folder.old")) {
      unlock_folder($folder);
      croak("can't unlink $folder.old: $!\n");
    }
  }

  unlock_folder($folder);

  return($qty_new_messages);
}

=head2 pack

Calls the superclass C<pack> method.  This is essentially a no-op
since mbox folders don't need to be packed.

=cut

sub pack { return($_[0]->SUPER::pack); }

=head2 get_message($msg_number)

=over 2

=item * Call the superclass C<get_message> method.

=item * Create a temporary file with the contents of the given mail
message.

=item * Absorb the temporary file into a B<Mail::Internet> object
reference.

=item * Delete the temporary file.

=item * Return the B<Mail::Internet> object reference.

=back

=cut

sub get_message {
  my $self = shift;
  my $key = shift;

  my $file;
  my $message;
  local(*FILE);

  return(undef) unless $self->SUPER::get_message($key);

  return(undef) if (!defined($self->{Messages}{$key}));

  $file = $self->extract_message($key, 1);

  if (!open(FILE, $file)) {
    unlink($file);
    croak("whoa! can't open $file: $!\n");
  }
  $message = new Mail::Internet(<FILE>);
  close(FILE);
  unlink($file);

  return($message);
}

=head2 get_header($msg_number)

If the particular header has never been retrieved then C<get_header>
loads (in a manner similar to C<get_message>) the header of the given
mail message into C<$self-E<gt>{Messages}{$msg_number}{Header}> and
returns the object reference.

If the header for the given mail message has already been retrieved in
a prior call to C<get_header>, then the cached entry is returned.

It also calls the superclass C<get_header> method.

=cut

sub get_header {
  my $self = shift;
  my $key = shift;

  my $file;
  my $header;
  local(*FILE);

  return(undef) if (!$self->SUPER::get_header($key) ||
		    !defined($self->{Messages}{$key}));

  return($self->{Messages}{$key}{Header}) if ($self->{Messages}{$key}{Header});
  
  $file = $self->extract_message($key, 0);

  if (!open(FILE, $file)) {
    unlink($file);
    croak("can't open $file: $!\n");
  }
  $header = new Mail::Internet;
  $header->read_header(\*FILE);
  close(FILE);
  unlink($file);
  $self->cache_header($key, $header);

  return($header);
}

=head2 append_message($message_ref)

=over 2

=item * Call the superclass C<append_message> method.

=item * Lock the folder.

=item * If a 'From ' line isn't present in C<$message_ref> then
synthesize one.

=item * Append the contents of C<$message_ref> to the folder.

=item * Adds a record of the new message in the internal data
structures of C<$self>.

=item * Unlock the folder.

=back

=cut

sub append_message {
  my $self = shift;
  my $message_ref = shift;

  my $file_pos;
  my $end_file_pos;
  my $message_number = $self->last_message;
  my $body;
  local(*FILE);

  return(0) unless $self->SUPER::append_message($message_ref);

  $body = $message_ref->body;
  open(FILE, ">>$self->{WorkingFile}") ||
    croak("can't append to $self->{WorkingFile}: $!\n");
  $file_pos = tell(FILE);
  print(FILE synth_envelope($message_ref), "\n")
    if (!$message_ref->get('From '));
  $message_ref->print(\*FILE);
  # actually, maybe we should always append a blank line
  print(FILE "\n") if ($body->[$#{$body}] ne "\n");
  $end_file_pos = tell(FILE);
  close(FILE);

  $message_number++;
  $self->remember_message($message_number);
  $self->{Messages}{$message_number}{MboxFilePos} = [$file_pos, 0];
  $self->{Messages}{$message_number}{MboxFilePos}[1] =
    $end_file_pos - (($message_ref->body->[$#{$message_ref->body}] eq "\n") ?
		     2 : 1);
  $self->sort_message_list;

  return(1);
}

# Mbox files must have a 'From ' line at the beginning of each
# message.  This routine will synthesize one from the 'From:' and
# 'Date:' fields.  Original solution and code of the following
# subroutine provided by Andreas Koenig

sub synth_envelope {
  my $message_ref = shift;
  my @addrs;
  my $from;
  my $date;

  @addrs = Mail::Address->parse($message_ref->get('From'));
  $from = $addrs[0]->address();
  $date = ctime(str2time($message_ref->get("date")));
  chomp($date);

  return("From $from  $date");
}

=head2 update_message($msg_number, $message_ref)

=over 2

=item * Call the superclass C<update_message> method.

=item * Writes a new copy of the working folder file replacing the
given message with the contents of the given B<Mail::Internet> message
reference.  It will synthesize a 'From ' line if one isn't present in
$message_ref.


=back

=cut

sub update_message {
  my $self = shift;
  my $key = shift;
  my $message_ref = shift;

  my $file_pos = 0;
  my $i = 1;
  local(*WORKFILE);
  local(*NEWWORKFILE);

  return(0) unless $self->SUPER::update_message($key, $message_ref);

  open(WORKFILE, $self->{WorkingFile}) ||
    croak("can't open $self->{WorkingFile}: $!\n");
  open(NEWWORKFILE, ">$self->{WorkingFile}N") ||
    croak("can't create $self->{WorkingFile}N: $!\n");
  chmod(0600, "$self->{WorkingFile}N") ||
    croak("can't chmod $self->{WorkingFile}N: $!\n");
  while (<WORKFILE>) {
    if (/^From /) {
      if ($i == $key) {
	print(NEWWORKFILE synth_envelope($message_ref), "\n")
	  if (!$message_ref->get('From '));
	$message_ref->print(\*NEWWORKFILE);
      }
      $i++;
    }
    print(NEWWORKFILE $_) if ($i != $key);
  }
  close(NEWWORKFILE);
  close(WORKFILE);
  $self->remember_mbox_points("$self->{WorkingFile}N", 0);

  rename($self->{WorkingFile}, "$self->{WorkingFile}O") ||
    croak("can't rename $self->{WorkingFile}: $!\n");
  rename("$self->{WorkingFile}N", $self->{WorkingFile}) ||
    croak("can't rename $self->{WorkingFile}N");
  unlink("$self->{WorkingFile}O");

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
  local(*FILE);

  return(0) if (-e $foldername);
  open(FILE, ">$foldername") || croak("can't create $foldername: $!\n");
  close(FILE);
  chmod(0600, $foldername) || croak("can't chmod $foldername: $!\n");
  return(1);
}
###############################################################################
sub DESTROY {
  my $self = shift;

  # all of these are just in case...
  # the appropriate methods should have removed them already...
  unlock_folder($self->foldername);
  unlink($self->{WorkingFile},
	 "$self->{WorkingFile}N",
	 "$self->{WorkingFile}O",
	 glob("$self->{MsgFilePrefix}.*"));
}

sub lock_folder {
  my $folder = shift;

  my $i = 3;
  local(*FILE);

  return(lock($folder));
  if (0) {
    while ($i--) {
      if (! -e "$folder.lock") {
	open(FILE, ">$folder.lock") ||
	  croak("can't create $folder.lock: $!\n");
	close(FILE);
	return(1);
      }
      sleep(3);
    }
    return(0);
  }
}

sub unlock_folder {
  return(unlock($_[0]));
  if (0) {
    return((-e "$_[0].lock") ? unlink("$_[0].lock") : 1);
  }
}

sub extract_message {
  my $self = shift;
  my $key = shift;
  my $full_message = shift;

  my $msg_file = "$self->{MsgFilePrefix}.$key";
  my $next_msg = $self->next_message($key);
  my $goal_pos =
    ($next_msg) ? $self->{Messages}{$next_msg}{MboxFilePos}->[0] : 0;

  local(*FOLDER);
  local(*FILE);

  open(FOLDER, $self->{WorkingFile}) ||
    croak("can't open $self->{WorkingFile}: $!\n");
  open(FILE, ">$msg_file") || croak("can't create $msg_file: $!\n");
  chmod(0600, $msg_file) || croak("can't chmod $msg_file: $!\n");
  seek(FOLDER, $self->{Messages}{$key}{MboxFilePos}->[0], 0) ||
    croak("can't seek to $self->{Messages}{$key}{MboxFilePos}->[0] in $self->{WorkingFile}: $!\n");
  while (<FOLDER>) {
    last if ($goal_pos && (tell(FOLDER) >= $goal_pos));
    last if (!$full_message && /^$/);
    print(FILE $_);
  }
  close(FILE);
  close(FOLDER);

  return($msg_file);
}

=head1 AUTHOR

Kevin Johnson E<lt>F<kjj@primenet.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
