# -*-perl-*-
#
# Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: Mbox.pm,v 1.1 1996/07/16 04:47:18 kjj Exp $

package Mail::Folder::Mbox;
@ISA = qw(Mail::Folder);

=head1 NAME

Mail::Folder::Mbox - A Unix mbox interface for Mail::Folder.

I<B<WARNING: This code is in alpha release.> Expect the interface to
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

=cut

use Mail::Folder;
use Mail::Internet;
use Carp;
use File::Tools;

use vars qw($VERSION);

$VERSION = "0.02";

$folder_id = 0;			# used to generate a unique id per open folder

=head1 METHODS

=head2 init()

Initializes various items specific to B<emaul>.

=item * Determines an appropriate temporary directory.

=item * Bumps a sequence number used for unique temporary filenames.

=item * Initializes C<$self-E<gt>{WorkingFile}> to the name of a file that
will be used to hold the temporary working of the folder.

=item * Initializes C<$self-E<gt>{MsgFilePrefix}> to a string that will be
used to create temporary filenames when extracting messages from the
folder.

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

=item * Call the superclass C<open> method.

=item * Lock the folder.

=item * Copy the folder to a temporary location as a working copy.

=item * Unlock the folder.

=item * For every message in the folder, add the message_number to the
object's list of messages.

=cut

sub open {
  my $self = shift;
  my $folder = shift;

  my $message_number = 0;
  my $file_pos = 0;
  local(*FILE);

  return(0) unless $self->SUPER::open($folder);

  lock_folder($folder) || return(0);

  if (!copy($folder, $self->{WorkingFile})) {
    unlock_folder($folder);
    croak("open can't create $self->{WorkingFile}: $!\n");
  }

  if (!unlock_folder($folder)) {
    unlink($self->{WorkingFile});
    return(0);
  }

  # still need to check to see if it's really an mbox file

  # need to figure out best way to remember the line number or
  # seek-position of the start of each message

  open(FILE, $self->{WorkingFile}) ||
    croak("open can't open $self->{WorkingFile}: $!\n");
  while (<FILE>) {
    if (/^From /) {
      $message_number++;
      $self->remember_message($message_number);
      $self->{Messages}{$message_number} = $file_pos;
    }
    $file_pos = tell(FILE);
  }
  close(FILE);
  $self->sort_message_list();

  $self->current_message(1);

  return(1);
}

=head2 close()

Deletes the working copy of the folder and calls the superclass
C<close> method.

=cut

sub close {
  my $self = shift;

  unlink($self->{WorkingFile});
  return($self->SUPER::close());
}

=head2 sync()

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

=cut

sub sync {
  my $self = shift;

  my $last_message_number;
  my $qty_new_messages = 0;
  my $i = 0;
  my @statary;
  my $folder = $self->foldername();
  my $tmpfolder = "$folder.$$";
  my $file_pos;

  local(*INFILE);
  local(*OUTFILE);

  return(-1) if ($self->SUPER::sync() == -1);

  if (!open(OUTFILE, ">>$self->{WorkingFile}")) {
    croak("sync can't append to $self->{WorkingFile}: $!\n");
  }
  chmod(0600, $self->{WorkingFile}) ||
    croak("sync can't chmod $self->{WorkingFile}: $!\n");

  $last_message_number = $self->last_message();

  return(-1) if (!lock_folder($folder));

  if (!open(INFILE, $folder)) {
    unlock_folder($folder);
    croak("sync can't open $folder: $!\n");
  }

  $file_pos = tell(INFILE);
  while (<INFILE>) {
    if (/^From /) {
      $i++;
      if ($i > $last_message_number) {
	$self->remember_message($i);
	$self->{Messages}{$i} = $file_pos;
	$qty_new_messages++;
      }
    }
    print(OUTFILE $_) if ($qty_new_messages);
    $file_pos = tell(INFILE);
  }
  close(INFILE);
  close(OUTFILE);
  $self->sort_message_list();

  # Create a new copy of the folder and populate it with the messages
  # in the working copy that aren't flagged for deletion.

  if (!open(OUTFILE, ">$tmpfolder")) {
    unlock_folder($folder);
    croak("sync can't create $tmpfolder: $!\n");
  }
  if (!open(INFILE, $self->{WorkingFile})) {
    unlock_folder($folder);
    croak("sync can't open $self->{WorkingFile}: $!\n");
  }
  @statary = stat(INFILE);
  if (!chmod(($statary[2] & 0777), $tmpfolder)) {
    unlink($tmpfolder);
    croak("sync can't chmod $tmpfolder: $!\n");
  }

  $i = 0;
  while (<INFILE>) {
    $i++ if (/^From /);
    print(OUTFILE $_) if (!defined($self->{Deletes}{$i}));
  }
  close(INFILE);
  close(OUTFILE);
  map {$self->forget_message($_)} $self->list_deletes();
  $self->clear_deletes();
  $self->sort_message_list();

  # Move the original folder to a temp location

  if (!rename($folder, "$folder.old")) {
    unlock_folder($folder);
    croak("sync can't move $folder out of the way: $!\n");
  }

  # Move the new folder into place

  if (!rename($tmpfolder, $folder)) {
    unlock_folder($folder);
    croak("sync gack! can't rename $folder.old to $folder: $!\n")
      if (!rename("$folder.old", $folder));
    croak("sync can't move $folder to $folder.old: $!\n");
  }

  # Delete the old original folder

  if (!unlink("$folder.old")) {
    unlock_folder($folder);
    croak("sync can't unlink $folder.old: $!\n");
  }

  # Unlock the folder
  unlock_folder($folder);

  return($qty_new_messages);
}

=head2 pack()

Calls the superclass C<pack> method.  This is essentially a no-op
since mbox folders don't need to be packed.

=cut

sub pack {
  my $self = shift;

  return($self->SUPER::pack());
}

=head2 get_message($msg_number)

=item * Call the superclass C<get_message> method.

=item * Create a temporary file with the contents of the given mail
message.

=item * Absorb the temporary file into a B<Mail::Internet> object
reference.

=item * Delete the temporary file.

=item * Return the B<Mail::Internet> object reference.

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
    croak("get_message can't open $file: $!\n");
  }
  $message = Mail::Internet->new(<FILE>);
  close(FILE);
  unlink($file);

  return($message);
}

=head2 get_header($msg_number)

If the particular header has never been retrieved then C<get_header>
loads (in a manner similar to C<get_message>) the header of the given
mail message into C<$self-E<gt>{Headers}{$msg_number}> and returns the
object reference.

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

  return($self->{Headers}{$key}) if ($self->{Headers}{$key});
  
  return(undef) unless $self->SUPER::get_header();

  return(undef) if (!defined($self->{Messages}{$key}));

  $file = $self->extract_message($key, 0);

  if (!open(FILE, $file)) {
    unlink($file);
    croak("get_header can't open $file: $!\n");
  }
  $header = Mail::Internet->new();
  $header->read_header(\*FILE);
  close(FILE);
  unlink($file);
  $self->cache_header($key, $header);

  return($header);
}

=head2 append_message($message_ref)

=item * Call the superclass C<append_message> method.

=item * Lock the folder.

=item * Append the contents of C<$message_ref> to the folder.

=item * Adds a record of the new message in the internal data
structures of C<$self>.

=item * Unlock the folder.

=cut

sub append_message {
  my $self = shift;
  my $message_ref = shift;

  my $file_pos;
  my $message_number = $self->last_message();
  local(*FILE);

  return(0) unless $self->SUPER::append_message($message_ref);

  open(FILE, ">>$self->{WorkingFile}") ||
    croak("append_message can't append to $self->{WorkingFile}: $!\n");
  $file_pos = tell(FILE);
  $message_ref->print(\*FILE);
  close(FILE);

  $message_number++;
  $self->remember_message($message_number);
  $self->{Messages}{$message_number} = $file_pos;
  $self->sort_message_list();

  return(1);
}

=head2 update_message($msg_number, $message_ref)

=item * Call the superclass C<update_message> method.

=item * Writes a new copy of the working folder file replacing the
given message with the contents of the given B<Mail::Internet> message
reference.

=cut

sub update_message {
  my $self = shift;
  my $key = shift;
  my $message_ref = shift;

  my $file_pos = 0;
  my $i = 1;
  local(*INFILE);
  local(*OUTFILE);

  return(0) unless $self->SUPER::update_message($key, $message_ref);

  open(INFILE, $self->{WorkingFile}) ||
    croak("can't open $self->{WorkingFile}: $!\n");
  open(OUTFILE, ">$self->{WorkingFile}N") ||
    croak("can't create $self->{WorkingFile}N: $!\n");
  chmod(0600, "$self->{WorkingFile}N") ||
    croak("can't chmod $self->{WorkingFile}N: $!\n");
  while (<INFILE>) {
    if (/^From /) {
      $message_ref->print(\*OUTFILE) if ($i == $key);
      $self->{Messages}{$i} = $file_pos;
      $i++;
    }
    print(OUTFILE $_) if ($i != $key);
    $file_pos = tell(OUTFILE);
  }
  close(OUTFILE);
  close(INFILE);

  rename($self->{WorkingFile}, "$self->{WorkingFile}O") ||
    croak("can't rename $self->{WorkingFile}: $!\n");
  rename("$self->{WorkingFile}N", $self->{WorkingFile}) ||
    croak("can't rename $self->{WorkingFile}N");
  unlink("$self->{WorkingFile}O");

  return(1);
}
###############################################################################
sub DESTROY {
  my $self = shift;

  # all of these are just in case...
  # the appropriate methods should have removed them already...
  unlock_folder($self->foldername());
  unlink($self->{WorkingFile},
	 "$self->{WorkingFile}N",
	 "$self->{WorkingFile}O",
	 glob("$self->{MsgFilePrefix}.*"));
}

sub lock_folder {
  my $folder = shift;

  my $i;
  local(*FILE);

  for ($i = 3; $i; $i--) {
    if (! -e "$folder.lock") {
      open(FILE, ">$folder.lock") || croak("can't create $folder.lock: $!\n");
      close(FILE);
      return(1);
    }
    sleep(3);
  }
  return(0);
}

sub unlock_folder {
  my $folder = shift;

  return((-e "$folder.lock") ? unlink("$folder.lock") : 1);
}

sub extract_message {
  my $self = shift;
  my $key = shift;
  my $full_message = shift;

  my $msg_file = "$self->{MsgFilePrefix}.$key";
  my $next_msg = $self->next_message($key);
  my $goal_pos = ($next_msg != -1) ? $self->{Messages}{$next_msg} : 0;

  local(*FOLDER);
  local(*FILE);

  open(FOLDER, $self->{WorkingFile}) ||
    croak("extract_message can't open $self->{WorkingFile}: $!\n");
  open(FILE, ">$msg_file") ||
    croak("extract_message can't create $msg_file: $!\n");
  chmod(0600, $msg_file) ||
    croak("extract_message can't chmod $msg_file: $!\n");
  seek(FOLDER, $self->{Messages}{$key}, 0) ||
    croak("extract_message can't seek to $self->{Messages}{$key} in $self->{WorkingFile}: $!\n");
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
