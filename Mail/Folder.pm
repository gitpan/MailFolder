# -*-perl-*-
#
# Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: Folder.pm,v 1.3 1996/08/03 17:32:21 kjj Exp $

require 5.002;			# maybe on older perl5s - haven't tested

package Mail::Folder;

=head1 NAME

Mail::Folder - A folder-independant interface to email folders.

B<WARNING: This code is in alpha release. Expect the interface to change>

=head1 SYNOPSIS

C<use Mail::Folder;>

=head1 DESCRIPTION

This base class, and it's subclasses provide an object-oriented
interface to email folders independant of the underlying folder
implementation.

There are currently two folder interfaces provided with this package:

=over 4

=item Mail::Folder::Emaul

=item Mail::Folder::Mbox

=back

Here's a snippet of code that retrieves the third message from a
mythical emaul folder and outputs it to stdout:

    use Mail::Folder::Emaul;

    $folder = new Mail::Folder('emaul', "mythicalfolder");
    $message = $folder->get_message(3);
    $message->print(\*STDOUT);
    $folder->close;

=head1 METHODS

=cut

use Carp;
use vars qw(%folder_types, $VERSION);

%folder_types = {};

$VERSION = "0.03";
###############################################################################

=head2 new([%options])

=head2 new($folder_name [, %options])

Create a new, empty B<Mail::Folder> object.  If C<$folder_name> is
specified, then the C<open> method will be automatically called with
that argument.

Options are specified as hash items using key and value pairs.
Currently, the only builtin option is C<Create>, which is used by
C<open>.

=cut

sub new {
  my $class  = shift;
  my $type = shift;
  my $folder;
  my %options;

  if ($#_ != -1) {
    $folder = shift if (!($#_ % 2));
    %options = @_;
  }

  my $concrete;
  my $self;
  
  ($concrete = $folder_types{$type}) or return undef;
  $self = bless {}, $concrete;
  
  $self->{Type} = $type;
  $self->{Filename} = '';
  $self->{Current} = 0;
  $self->{Messages} = {};
  $self->{SortedMessages} = [];
  $self->{Readonly} = 0;
  $self->{Options} = {%options};

  return(undef) if (!$self->init);

  $self->open($folder) if (defined($folder));
  
  return $self;
}
###############################################################################

=head2 open($folder_name)

Open the given folder and populate internal data structures with
information about the messages in the folder.  If the C<Create> option
is set, then the folder will be created if it does not already exist.

The readonly attribute will be set if the underlying folder interface
determines that the folder is readonly.

=cut

sub open {
  my $self = shift;
  my $filename = shift;

  ($filename) || croak("open needs a parameter");

  $self->create($filename) if ($self->get_option('Create'));

  $self->{Filename} = $filename;
}

=head2 close

Perform any housecleaning to affect a 'closing' of the folder.  It
does not perform an implicit C<sync>.  Make sure you do a C<sync>
before the C<close> if you want the pending deletes, appends, updates,
and the like to be performed on the folder.

=cut

sub close {
  my $self = shift;
  
  $self->{Filename} = '';
  $self->{Current} = 0;
  $self->{Messages} = {};
  $self->{SortedMessages} = [];
  $self->{Readonly} = 0;
  
  return(1);
}

=head2 sync

Synchronize the folder with the internal data structures.  The folder
interface will process deletes, updates, appends, refiles, and dups.
It also reads in any new messages that have arrived in the folder
since the last time it was either C<open>ed or C<sync>ed.

=cut

sub sync {
  return(($_[0]->foldername eq '') ? -1 : 0);
}

=head2 pack

For folder formats that may have holes in the message number sequence
(like mh) this will rename the files in the folder so that there are
no gaps in the message number sequence.  For folder formats that won't
have these holes (like mbox) it does nothing.

=cut

sub pack {
  return(1);
}
###############################################################################

=head2 get_message($msg_number)

Retrieve a message.  Returns a reference to a B<Mail::Internet> object.

=cut

sub get_message {
  return($_[0]->foldername ne '');
}

=head2 get_header($msg_number)

Retrieve a message header.  Returns a reference to a B<Mail::Internet> object.

=cut

sub get_header {
  return($_[0]->foldername ne '');
}
###############################################################################

=head2 append_message($message_ref)

Add a message to a folder.  Given a reference to a B<Mail::Internet>
object, append it to the end of the folder.  The result is not
committed to the original folder until a C<sync> is performed.

=cut

sub append_message {
  return($_[0]->foldername ne '');
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

  return(0) if (($self->foldername eq '') ||
		!defined($self->{Messages}{$key}));

  $self->invalidate_header($key);
  return($self->add_label($key, 'edited'));
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
  
  return(0) if (!$message ||
		!$folder->append_message($message) ||
		!$self->delete_message($msg));

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

  return($message && $folder->append_message($message));
}
###############################################################################

=head2 init

This is a stub entry called by C<new>.  The primary purpose is to
provide a method for subclasses to override for initialization to be
performed at constructor time.  It is called after the object members
variables have been initialized and before the optional call to
C<open>.  The C<new> method will return C<undef> if the C<init> method
returns C<0>.

=cut

sub init {
  return(1);
}
###############################################################################

=head2 delete_message($msg_number)

Mark a message for deletion.  The actual deletion will be done by the
C<sync> method.  The actual delete in the original folder is not
performed until a C<sync> is performed.

=cut

sub delete_message {
  my $self = shift;
  my $key = shift;
  
  return(0) if (!defined($self->{Messages}{$key}));

  return($self->add_label($key, 'delete'));
}

=head2 message_list

Returns a list of the message numbers in the folder.

=cut

sub message_list {
  return(@{$_[0]->{SortedMessages}});
}
###############################################################################

=head2 first_message

Returns the message number of the first message in the folder.

=cut

sub first_message {
  my @message_list = $_[0]->message_list;
  return(0) if ($#message_list == -1);
  return(shift(@message_list));
}

=head2 last_message

Returns the message number of the last message in the folder.

=cut

sub last_message {
  my @message_list = $_[0]->message_list;
  return(0) if ($#message_list == -1);
  return(pop(@message_list));
}

=head2 next_message($msg_number)

Returns the message number of the next message in the folder relative
to C<$msg_number>.  It returns C<0> is there is no next message
(ie. at the end of the folder).

=cut

sub next_message {
  my $self = shift;
  my $msg_number = shift;
  
  my $last_message = $self->last_message;

  while (++$msg_number <= $last_message) {
    return $msg_number if (defined($self->{Messages}{$msg_number}));
  }
  return(0);
}

=head2 prev_message($msg_number)

Returns the message number of the previous message in the folder
relative to C<$msg_number>.  It returns C<0> is there is no previous
message (ie. at the beginning of the folder).

=cut

sub prev_message {
  my $self = shift;
  my $msg_number = shift;
  
  my $first_message = $self->first_message;

  while (--$msg_number >= $first_message) {
    return $msg_number if (defined($self->{Messages}{$msg_number}));
  }
  return(0);
}
###############################################################################

=head2 first_labeled_message($label)

Returns the message number of the first message in the folder that has
the label $label associated with it.  Returns C<0> is there are no
messages with the given label.

=cut

sub first_labeled_message {
  my $self = shift;
  my $label = shift;

  my $msg;

  for ($self->message_list) {
    return $_ if ($self->label_exists($_, $label));
  }
  return(0);
}

=head2 first_labeled_message($label)

Returns the message number of the last message in the folder that has
the label $label associated with it.  Returns C<0> if there are no
messages with the given label.

=cut

sub last_labeled_message {
  my $self = shift;
  my $label = shift;

  my $msg;

  for (reverse($self->message_list)) {
    return $_ if ($self->label_exists($_, $label));
  }
  return(0);
}

=head2 next_labeled_message($msg_number, $label)

Returns the message number of the next message (relative to
C<$msg_number>) in the folder that has the label C<$label> associated
with it.  It returns C<0> is there is no next message with the given
label.

=cut

sub next_labeled_message {
  my $self = shift;
  my $msg_number = shift;
  my $label = shift;
  
  my $last_message = $self->last_message;

  while (++$msg_number <= $last_message) {
    return $msg_number if (defined($self->{Messages}{$msg_number}) &&
			   $self->label_exists($msg_number, $label));
  }
  return(0);
}

=head2 prev_labeled_message($msg_number, $label)

Returns the message number of the previous message (relative to
C<$msg_number>) in the folder that has the label C<$label> associated
with it.  It returns C<0> is there is no previous message with the
given label.

=cut

sub prev_labeled_message {
  my $self = shift;
  my $msg_number = shift;
  my $label = shift;
  
  my $first_message = $self->first_message;

  while (--$msg_number >= $first_message) {
    return $msg_number if (defined($self->{Messages}{$msg_number}) &&
			   $self->label_exists($msg_number, $label));
  }
  return(0);
}
###############################################################################

=head2 current_message

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

  return($self->{Current} = $key);
}
###############################################################################

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
			       $self->get_header($b))} $self->message_list);
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
	      $self->message_list));
}
###############################################################################

=head2 add_label($msg_number, $label)

Associates C<$label> with C<$msg_number>.  The label must have a
length E<gt> 0 and should be a printable string, although there are
currently no requirements for this.

C<add_label> will return C<0> if C<$label> is of zero length,
otherwise it returns C<1>.

The persistant storage of labels is dependant on the underlying folder
interface.  Some folder interfaces may not support arbitrary labels.
In this case, the labels will not exist when the folder is reopened.

There are a few standard labels that have implied meaning.  Unless
stated, these labels are not actually acted on my the module
interface, rather represent a standard set of labels for MUAs to use.

=over 2

=item * deleted

This is used by the C<delete_message> and C<sync> to process the
deletion of messages.  These will not be reflected in any persistant
storage of message labels.

=item * edited

This tag is added by C<update_message> to reflect that the message has
been altered.  This behaviour may go away.

=item * seen

This means that the message has been viewed by the user.  This should
only be set by MUAs that present the entire message body to the user.

=item * filed

=item * replied

=item * forwarded

=item * printed

=back

=cut

sub add_label {
  my $self = shift;
  my $msg_number = shift;
  my $label = shift;

  return(0) if (!length($label));
  $self->{Messages}{$msg_number}{Labels}{$label}++;
  return(1);
}

=head2 delete_label($msg_number, $label)

Deletes the association of C<$label> with C<$msg_number>.

Returns C<0> if the label C<$label> wasn't associated with
C<$msg_number>, otherwise returns a C<1>.

=cut

sub delete_label {
  my $self = shift;
  my $msg_number = shift;
  my $label = shift;

  return(0) if (!defined($self->{Messages}{$msg_number}{Labels}) ||
		!defined($self->{Messages}{$msg_number}{Labels}{$label}));

  delete $self->{Messages}{$msg_number}{Labels}{$label};
  return(1);
}

=head2 clear_label($label)

Deletes the association of C<$label> for all of the messages in the
folder.

Returns the quantity of messages that were associated with the label
before they were cleared.

=cut

sub clear_label {
  my $self = shift;
  my $label = shift;

  my $qty = 0;
  my $msg;

  for ($self->message_list) {
    $qty += $self->delete_label($_, $label);
  }
  return($qty);
}

=head2 label_exists($msg_number, $label)

Returns C<1> if the label C<$label> is associated with C<$msg_number>
otherwise returns C<0>.

=cut

sub label_exists {
  my $self = shift;
  my $msg_number = shift;
  my $label = shift;

  return($self->message_exists($msg_number) &&
	 defined($self->{Messages}{$msg_number}{Labels}) &&
	 defined($self->{Messages}{$msg_number}{Labels}{$label}));
}

=head2 list_labels($msg_number)

Returns a list of the labels that are associated with C<$msg_number>.

=cut

sub list_labels {
  my $self = shift;
  my $msg_number = shift;

  return(defined($self->{Messages}{$msg_number}{Labels}) ?
	 sort keys %{$self->{Messages}{$msg_number}{Labels}} :
	 ());
}

=head2 list_all_labels

Returns a list of all the labels that are associated with the messages
in the folder.

=cut

sub list_all_labels {
  my $self = shift;
  my %alllabels;
  my $msg;
  my $label;

  foreach $msg ($self->message_list) {
    for ($self->list_labels($msg)) {
      $alllabels{$_}++;
    }
  }
  return(sort keys %alllabels);
}

=head2 select_label($label)

Returns a list of message numbers that have the given label C<$label>
associated with them.

=cut

sub select_label {
  my $self = shift;
  my $label = shift;
  my $msg;
  my @msgs;

  for ($self->message_list) {
    push(@msgs, $_) if (defined($self->{Messages}{$_}{Labels}) &&
			  defined($self->{Messages}{$_}{Labels}{$label}));
  }
  return(@msgs);
}
###############################################################################

=head2 foldername

Returns the name of the folder that the object has open.

=cut

sub foldername {
  return($_[0]->{Filename});
}

=head2 message_exists($msg_number)

Returns C<1> if the folder object contains a reference for
C<$msg_number>, otherwise returns C<0>.

=cut

sub message_exists {
  return(defined($_[0]->{Messages}{$_[1]}));
}

=head2 set_readonly

Sets the C<readonly> attribute for the folder.  This will cause the
C<sync> command to not perform any updates to the actual folder.

=cut

sub set_readonly {
  $_[0]->{Readonly} = 1;
}

=head2 is_readonly

Returns C<1> if the C<readonly> attribute for the folder is set,
otherwise returns C<0>.

=cut

sub is_readonly {
  return($_[0]->{Readonly});
}

=head2 get_option($option)

Returns the setting for the given option.  Returns C<undef> if the
option does not exist.

=cut

sub get_option {
  my $self = shift;
  my $option = shift;

  return undef if (!defined($self->{Options}{$option}));
  return($self->{Options}{$option});
}

=head2 set_option($option, $value)

Set C<$option> to C<$value>.

=cut

sub set_option {
  my $self = shift;
  my $option = shift;
  my $value = shift;

  $self->{Options}{$option} = $value;
}
###############################################################################

=head1 WRITING A FOLDER INTERFACE

The start of a new folder interface module should start with something
along the lines of the following chunk of code:

    package Mail::Folder::YOUR_FOLDER_TYPE;
    @ISA = qw(Mail::Folder);
    use Mail::Folder;

    Mail::Folder::register_folder_type(Mail::Folder::YOUR_FOLDER_TYPE,
				       'your_folder_type_name');

In general, writing a folder interface consists of writing a set of
methods that overload some of the native ones in C<Mail::Folder>.
Below is a list of the methods and specific tasks that each must
perform.  See the code of the folder interfaces provides with the
package for specific examples.

If you go about writing a folder interface and find that something is
missing from this documentation, please let me know.

=head2 open

=over 2

=item * Call the superclass C<new> method.

=item * Call C<set_readonly> if folder isn't writable.

=item * Call C<remember_message> for each message in the folder.

=item * Call C<sort_message_list>.

=item * Initialize C<current_message>.

=item * Initialize any message labels from the folder's persistant storage.

=back

=head2 close

=over 2

=item * Call the superclass C<close> method.

=back

=head2 sync

=over 2

=item * Call the superclass C<sync> method.

=item * Lock the folder.

=item * Absorb any new messages

=item * Perform any pending deletes and updates.

=item * Update the folder's persistant storage of current message.

=item * Update the folder's persistant storage of message labels.

=item * Unlock the folder.

=back

=head2 pack

=over 2

=item * Call the superclass C<pack> method.

=item * Perform the guts of the pack

=item * Renumber the C<Messages> member of $self.

=item * Call C<sort_message_list>

=item * Don't forget to reset current_message based on the renumbering.

=back

=head2 get_header

=over 2

=item * Call the superclass C<get_header> method.

=item * Return the cached entry if it exists.

=item * Extract the header into a C<Mail::Internet> object.

=item * Cache it.

=back

=head2 get_message

=over 2

=item * Call the superclass C<get_message> method.

=item * Extract the message into a C<Mail::Internet> object.

=back

=head2 update_message

=over 2

=item * Call the superclass C<update_message> method.

=item * Replace the specified message in the working copy of the folder.

=back

=head2 create

=over 2

=item * Create a folder in a manner specific to the folder interface.

=back

=head2 init

This isn't really a method that needs to be overloaded.  It is a
method that is called by C<new> to perform any initialization specific
to the folder interface.  For example of a typical use, see the
C<init> routine in C<Mail::Folder::Mbox>.

=head1 FOLDER INTERFACE METHODS

These routines are intended for use by implementers of finder
interfaces.

=head2 register_folder_type($class, $type)

Registers a folder interface with Mail::Folder.

=cut

sub register_folder_type {
  $folder_types{$_[1]} = $_[0];
}

=head2 sort_message_list

This is used to resort the internal sorted list of messages.  It needs
to be called whenever the list of messages is changed.  It's a
separate routine to allow large updates to the list of messages (like
during an C<open>) with only one trailing call to
C<sort_message_list>.

=cut

sub sort_message_list {
  $_[0]->{SortedMessages} = [sort { $a <=> $b } keys %{$_[0]->{Messages}}];
}

=head2 cache_header($msg_number, $header_ref)

Associates C<$header_ref> with C<$msg_number> in the object's internal
header cache.

=cut

sub cache_header {
  $_[0]->{Messages}{$_[1]}{Header} = $_[2];
}

=head2 invalidate_header($msg_number)

Clobbers the header cache entry for C<$msg_number>.

=cut

sub invalidate_header {
  delete $_[0]->{Messages}{$_[1]}{Header};
}

sub remember_message {
  $_[0]->{Messages}{$_[1]} = {};
  $_[0]->{Messages}{$_[1]}{Header} = undef;
}

sub forget_message {
  delete $_[0]->{Messages}{$_[1]};
  $_[0]->invalidate_header($_[1]);
}

=head1 AUTHOR

Kevin Johnson E<lt>F<kjj@primenet.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
