# -*-perl-*-
#
# Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: Folder.pm,v 1.2 1996/07/16 04:47:18 kjj Exp $

require 5.002;			# maybe on older perl5s - haven't tested

package Mail::Folder;

=head1 NAME

Mail::Folder - A folder-independant interface to email folders.

I<B<WARNING: This code is in alpha release.>
Expect the interface to change.>

=head1 SYNOPSIS

C<use Mail::Folder;>

=head1 DESCRIPTION

This base class, and it's subclasses provide an object-oriented
interface to email folders independant of the underlying folder
implementation.

There are currently two folder interfaces provided with this package:

=item Mail::Folder::Emaul

=item Mail::Folder::Mbox

The documentation for each of these modules provides more detailed
into on their operation.

=head1 ABSTRACT METHODS

These are the methods that a folder interface will override to perform
it's work on a folder.  The corresponding subclass methods should call
these methods if the call fails.

=cut

use Carp;
use vars qw(%folder_types, $VERSION);

%folder_types = {};

$VERSION = "0.02";

=head2 new()

=head2 new($folder_name)

Create a new, empty B<Mail::Folder> object.  If C<$folder_name> is
included, then the C<open> method is also called with that argument.

=cut

sub new {
  my $class  = shift;
  my $type = shift;
  my $folder = shift;
  
  my $concrete;
  my $self;
  
  ($concrete = $folder_types{$type}) or return undef;
  $self = bless {}, $concrete;
  
  $self->{Type} = $type;
  $self->{Current} = 0;
  $self->{Messages} = {};
  $self->{Headers} = {};
  $self->{Filename} = '';
  $self->{Deletes} = {};
  $self->{SortedMessages} = [];

  return(undef) if (!$self->init());
  
  $self->open($folder) if (defined($folder));
  
  return $self;
}
###############################################################################
=back

=head2 open($folder_name)

Open the given folder and populate internal data structures with
information about the messages in the folder.

=cut

sub open {
  my $self = shift;
  my $filename = shift;

  ($filename) || croak("open needs a parameter");
  stat($filename) || croak("can't open $filename: $!");

  $self->{Filename} = $filename;
}

=head2 close()

Perform any housecleaning to affect a 'closing' of the folder.  It
does not perform an implicit C<sync>.  Make sure you do a C<sync>
before the C<close> if you want the pending deletes and the like to be
performed on the folder.

=cut

sub close {
  my $self = shift;
  
  $self->{Filename} = '';
  $self->{Messages} = {};
  $self->{Headers} = {};
  $self->clear_deletes();
  
  return(1);
}

=head2 sync()

Synchronize the folder with the internal data structures.  The folder
interface will process deletes, updates, appends, refiles, and dups.
It also reads in any new messages that have arrived in the folder
since the last time it was either C<open>ed or C<sync>ed.

=cut

sub sync {
  my $self = shift;

  return(($self->foldername() eq '') ? -1 : 0);
}

=head2 pack()

For folder formats that may have holes in the message number sequence
(like mh) this will rename the files in the folder so that there are
no gaps in the message number sequence.  For folder formats that won't
have these holes (like mbox) it does nothing.

=cut

sub pack {
  my $self = shift;

  return(($self->list_deletes()) ? 0 : 1);
}

=head2 get_message($msg_number)

Retrieve a message.  Returns a reference to a B<Mail::Internet> object.

=cut

sub get_message {
  my $self = shift;
  my $key = shift;
  
  return($self->foldername() ne '');
}

=head2 get_header($msg_number)

Retrieve a message header.  Returns a reference to a B<Mail::Internet> object.

=cut

sub get_header {
  my $self = shift;
  my $key = shift;

  return($self->foldername() ne '');
}

=head2 append_message($message_ref)

Add a message to a folder.  Given a reference to a B<Mail::Internet>
object, append it to the end of the folder.  The result is not
committed to the original folder until a C<sync> is performed.

=cut

sub append_message {
  my $self = shift;
  my $mref = shift;
  
  return($self->foldername ne '');
}

=head2 update_message($msg_number, $message_ref)

Replaces the message identified by C<$msg_number> with the contents of
the message in reference to a B<Mail::Internet> object $message_ref.
The result is not committed to the original folder until a C<sync> is
performed.

=cut

sub update_message {
  my $self = shift;
  my $key = shift;
  my $mref = shift;

  if (($self->foldername() eq '') ||
      !defined($self->{Messages}{$key})) {
    return(0);
  }
  $self->invalidate_header($key);
  return(1);
}

=head2 init()

This is a stub entry called by C<new>.  The primary purpose is to
provide a method for subclasses to override for initialization to be
performed at constructor time.  It is called after the object members
variables have been initialized and before the optional call to
C<open>.  The C<new> method will reutrn C<undef> if the C<init> method
returns C<0>.

=cut

sub init {
  my $self = shift;

  return(1);
}
###############################################################################
=back

=head1 Class Methods

These methods are provided by the base class and probably don't need
to be overridden by a folder interface.

=head2 delete_message($msg_number)

Mark a message for deletion.  The actual deletion will be done by the
C<sync> method.  The actual delete in the original folder is not
performed until a C<sync> is performed.

=cut

sub delete_message {
  my $self = shift;
  my $key = shift;
  
  return(0) if (!defined($self->{Messages}{$key}));

  $self->{Deletes}{$key} = $key;
  return(1);
}

=head2 message_list()

Returns a list of the message numbers in the folder.

=cut

sub message_list {
  my $self = shift;

  return(@{$self->{SortedMessages}});
}

=head2 first_message()

Returns the message number of the first message in the folder.

=cut

sub first_message {
  my $self = shift;
  
  my @message_list = $self->message_list();
  
  return(shift(@message_list));
}

=head2 last_message()

Returns the message number of the last message in the folder.

=cut

sub last_message {
  my $self = shift;

  my @message_list = $self->message_list();
  
  return(pop(@message_list));
}

=head2 next_message()

=head2 next_message($msg_number)

Returns the message number of the next message in the folder.  If
C<$msg_number> is not specified it is relative to the current message,
otherwise it is relative to C<$msg_number>.  It returns C<-1> is there
is no next message (ie. at the end of the folder).

=cut

sub next_message {
  my $self = shift;
  my $key = shift;
  
  my $message = defined($key) ? $key : $self->current_message();
  my $last_message = $self->last_message();

  while ($message <= $last_message) {
    $message++;
    return $message if (defined($self->{Messages}{$message}));
  }
  return(-1);
}

=head2 prev_message()

Returns the message number of the previous message in the folder.  If
C<$msg_number> is not specified it is relative to the current message,
otherwise it is relative to C<$msg_number>.  It returns C<-1> is there
is no previous message (ie. at the beginning of the folder).

=cut

sub prev_message {
  my $self = shift;
  
  my $message = $self->current_message();
  my $first_message = $self->first_message();

  while ($message >= $first_message) {
    $message--;
    return $message if (defined($self->{Messages}{$message}));
  }
  return(-1);
}

=head2 current_message()

=head2 current_message($msg_number)

When called with no arguments returns the message number of the
current message in the folder.  When called with an argument set the
current message number for the folder to the value of the argument.

For folder mechanisms that provide persistant storage of the current
message, the underlying folder interface will update that storage.
For those that don't changes to C<current_message> will be affect
while the folder is open.

=cut

sub current_message {
  my $self = shift;
  my $key = shift;

  return($self->{Current}) if (!defined($key));

  $self->{Current} = $key;
  return(1);
}

=head2 sort($func_ref)

Returns a sorted list of messages.  It works conceptually similar to
the regular perl C<sort>.  The C<$func_ref> that is passed to C<sort>
must be a reference to a function.  The function will be passed two
B<Mail::Internet> message references containing only the headers and
it must return an integer less than, equal to, or greater than 0,
depending on how the elements of the array are to be ordered.

=cut

sub sort {
  my $self = shift;
  my $sort_func_ref = shift;

  return(sort {&$sort_func_ref($self->get_header($a),
			       $self->get_header($b))} $self->message_list());
}

=head2 select($func_ref)

Returns a list of message numbers that match a set of criteria.  The
method is passed a reference to a function that is used to determine
the match criteria.  The function will be passed a reference to a
B<Mail::Internet> message object containing only a header.

=cut

sub select {
  my $self = shift;
  my $select_func_ref = shift;

  return(grep(&{$select_func_ref}($self->get_header($_)),
	      $self->message_list()));
}

=head2 refile($msg_number, $folder_ref)

Moves a message from one folder to another.  Note that this method
uses C<delete_message> and C<append_message> so the changes will show
up in the folder objects, but will need a C<sync>s performed in order
for the changes to show up in the actual folders.

=cut

sub refile {
  my $self = shift;
  my $msg = shift;
  my $folder = shift;
  
  my $message = $self->get_message($msg);
  
  return(0) if (!$message);
  return(0) if (!$folder->append_message($message));
  return(0) if (!$self->delete_message($msg));
  return(1);
}

=head2 dup($msg_number, $folder_ref)

Copies a message to a folder.  Works like C<refile>, but doesn't
delete the original message.  Note that this method uses
C<append_message> so the change will show up in the folder object, but
will need a C<sync> performed in order for the change to show up in
the actual folder.

=cut

sub dup {
  my $self = shift;
  my $msg = shift;
  my $folder = shift;
  
  my $message = $self->get_message($msg);
  
  return(0) if (!$message);
  return(0) if (!$folder->append_message($message));
  return(1);
}

=head2 foldername()

Returns the name of the folder that the object has open.

=cut

sub foldername {
  my $self = shift;

  return($self->{Filename});
}

=head2 list_deletes()

Returns a list of the message numbers that are marked for deletion.

=cut

sub list_deletes {
  my $self = shift;

  return(sort keys %{$self->{Deletes}});
}

=head2 clear_deletes()

Zero out the list of pending deletes.

=cut

sub clear_deletes {
  my $self = shift;

  $self->{Deletes} = undef;
}
###############################################################################
=back

=head1 Misc Routines

=head2 register_folder_type($class, $type)

Register a folder interface with Mail::Folder.

=cut

sub register_folder_type {
  my $class = shift;
  my $type = shift;
  
  $folder_types{$type} = $class;
}
###############################################################################
=back

=head1 Folder Interface Methods

These routines are intended for use by implementers of finder
interfaces.

=head2 sort_message_list()

This is used to resort the internal sorted list of messages.  It needs
to be called whenever the list of messages is changed.  It's a
separate routine to allow large updates to the list of messages (like
during an C<open>) with only one trailing call to
C<sort_message_list>.

=cut

sub sort_message_list {
  my $self = shift;
  $self->{SortedMessages} = [sort { $a <=> $b } keys %{$self->{Messages}}];
}

=head2 cache_header($msg_number, $header_ref)

Associates C<$header_ref> with C<$msg_number> in the object's internal
header cache.

=cut

sub cache_header {
  my $self = shift;
  my $key = shift;
  my $header_ref = shift;

  $self->{Headers}{$key} = $header_ref;
}

=head2 invalidate_header($msg_number)

Clobbers the header cache entry for C<$msg_number>.

=cut

sub invalidate_header {
  my $self = shift;
  my $key = shift;

  delete $self->{Headers}{$key};
}

sub remember_message {
  my $self = shift;
  my $key = shift;
  
  $self->{Messages}{$key} = 0;
  $self->{Headers}{$key} = 0;
}

sub forget_message {
  my $self = shift;
  my $key = shift;
  
  delete $self->{Messages}{$key};
  $self->invalidate_header($key);
}
=head1 AUTHOR

Kevin Johnson E<lt>F<kjj@primenet.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
