# -*-perl-*-
#
# Copyright (c) 1996-1997 Kevin Johnson <kjj@pobox.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.
#
# $Id: Folder.pm,v 1.5 1997/03/18 02:37:38 kjj Exp $

require 5.003;

package Mail::Folder;
use strict;
use Carp;
use vars qw($VERSION %folder_types);
use MIME::Head;
use MIME::Parser;

$VERSION = "0.05";

=head1 NAME

Mail::Folder - A folder-independant interface to email folders.

B<WARNING: This code is in alpha release. Expect the interface to change.>

=head1 SYNOPSIS

C<use Mail::Folder;>

=head1 DESCRIPTION

This base class, and companion subclasses provide an object-oriented
interface to email folders independant of the underlying folder
implementation.

There are currently three folder interfaces provided with this package:

=over 4

=item Mail::Folder::Mbox

Ye olde standard mailbox format.

=item Mail::Folder::Maildir

An interface to maildir (ala qmail) folders.  This is a very
interesting folder format.  It is 'missing' some of the nicer features
that some other folder interfaces have (like the message sequences in
MH), but is probably one of the more resilient folder formats around.

=item Mail::Folder::Emaul

Emaul is a folder interfaces of my own design (in the loosest sense of
the word :-).  It is vaguely similar to MH.  I wrote it to flesh out
earlier versions of the C<Mail::Folder> package.

=back

Here is a snippet of code that retrieves the third message from a
mythical emaul folder and outputs it to stdout:

    use Mail::Folder::Emaul;

    $folder = new Mail::Folder('emaul', "mythicalfolder");
    $message = $folder->get_message(3);
    $message->print(\*STDOUT);
    $folder->close;

=head1 METHODS

=cut

%folder_types = ();

###############################################################################

=head2 new($foldertype [, %options])

=head2 new($foldertype, $folder_name [, %options])

Create a new, empty B<Mail::Folder> object of the specified folder
type.  If C<$folder_name> is specified, then the C<open> method will
be automatically called with that argument.

If C<$foldertype> is C<'AUTODETECT'> then the foldertype is deduced by
querying each registered foldertype for a match.

Options are specified as hash items using key and value pairs.

There are currently four builtin options:

=over 2

=item * Create

If set, C<open> will create the folder if it does not already exist.

=item * Content-Length

If set, the Content-Length header field will be automatically created
or updated by the C<append_message> and C<update_message> methods.

=item * DotLock

If set and appropriate for the folder interface, the folder interface
will use '.lock' style folder locking.  Currently, this is only used
by the mbox interface.  This mechanism might be replaced with
something more generalized in the future.

=item * NotMUA

If the option is set, the folder interface will still make updates
like deletes and appends, and the like, but will not save the message
labels or the current message indicator.

If the option is not set (the default), the folder interface will save
the persistant labels and the current message indicator as appropriate
for the folder interface.

The default setting is designed for the types of updates to the state
of mail mssages that a Mail User Agent typically makes.  Programmatic
updates to folders might be better served to turn the option off so
that labels like 'seen' aren't inadvertantly set and saved when they
really shouldn't be.

=item * Timeout

If this options is set, the folder interface will use it to override
any default value for Timeout.  For folder interfaces that entail
network communications it is used to specify the maximum amount of
time, in seconds, to wait for a response from the server.  For folder
interfaces that entail local file locking it is used to specify the
maximum amount of time, in seconds, to wait for a lock to be acquired.
And for the C<maildir> interface it is, of course, meaningless C<:-)>.

=back

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

  # error handling for this chunk of code needs to be better thought out.
  # actually, the open method is really the place to specify what type of
  # folder it is.
  if ($type eq 'AUTODETECT') {
    defined($folder)
      or croak("can't AUTODETECT without providing foldername: $!\n");
    $type = _detect_folder_type($folder)
      or croak("can't AUTODETECT foldertype for $folder\n")
  }
  
  ($concrete = $folder_types{$type}) or return undef;
  $self = bless {}, $concrete;
  
  $self->{Type} = $type;
  $self->{Name} = '';
  $self->{Current} = 0;
  $self->{Messages} = {};
				# each member of Messages member has the
				# following submembers:
				#    EnvelopeFrom
				#    EnvelopeTo (tbd)
				#    Header
				#    Labels
				# subclasses may add others
  $self->{Readonly} = 0;
  $self->{Options} = {%options};
  # The following variable tells the object what PID created the object.
  # This allows code to detect whether the creator is executing code
  # against the object of a child process is.  This is important if
  # you have code that creates temp files and do not want a forked child
  # to trigger a DESTROY method on exit.
  # Thanks to mjd@plover.com (Mark-Jason Dominus) for this solution.
  # This is a good point to bring up an important concept for this package.
  # If you use fork, it is a 'good thing' to only have the parent do
  # anything to the folder.  Any changes to the folder performed by a
  # child will cause the data structures in the parent to be out of sync
  # with the folder.  This would be a 'bad thing'.
  $self->{Creator} = $$;

  return undef if (!$self->init);

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

Please note that I have not done any testing for using this module
against system folders.  I am a strong advocate of using a filter
package or using a mail delivery agent that migrates the incoming
email to the home directory of the user.  If you try to use
C<MailFolder> against a system folder, you deserve what you get.
Consider yourself warned.  I have no intention, at this point in time,
to deal with system folders and any possible sgid-mail issues.  If you
work on it, and get it working, let me know.

The folder interface is expected to perform the following tasks:

=over 2

=item * Call the superclass C<new> method.

=item * Call C<set_readonly> if folder is not writable.

=item * Call C<remember_message> for each message in the folder.

=item * Initialize C<current_message>.

=item * Initialize any message labels from the persistant storage that
the folder has.

=back

=cut

sub open {
  ($_[1]) or croak("open needs a foldername parameter");
  $_[0]->create($_[1]) if ($_[0]->get_option('Create'));
  $_[0]->{Name} = $_[1];
}

=head2 close

Performs any housecleaning to affect a 'closing' of the folder.  It
does not perform an implicit C<sync>.  Make sure you do a C<sync>
before the C<close> if you want the pending deletes, appends, updates,
and the like to be performed on the folder.

The folder interface is expected to perform the following tasks:

=over 2

=item * Appropriate cleanup specific to the folder interface.

=item * Return the result of calling the superclass C<close> method.

=back

=cut

sub close {
  $_[0]->{Name} = '';
  $_[0]->{Current} = 0;
  $_[0]->{Messages} = {};
  $_[0]->{Readonly} = 0;
  
  return 1;
}

=head2 sync

Synchronize the folder with the internal data structures.  The folder
interface will process deletes, updates, appends, refiles, and dups.
It also reads in any new messages that have arrived in the folder
since the last time it was either C<open>ed or C<sync>ed.

The folder interface is expected to perform the following tasks:

=over 2

=item * Call the superclass C<sync> method.

=item * Lock the folder.

=item * Absorb any new messages

=item * Perform any pending deletes and updates.

=item * Update the folder persistant storage of current message.

=item * Update the folder persistant storage of message labels.

=item * Unlock the folder.

=back

=cut

sub sync {
  return(($_[0]->foldername ne '') ? 0 : -1);
}

=head2 pack

For folder formats that may have holes in the message number sequence
(like mh) this will rename the files in the folder so that there are
no gaps in the message number sequence.

Please remember that because this method might renumber the messages
in a folder.  Any code that remembers message numbers outside of the
object could get out of sync after a C<pack>.

The folder interface is expected to perform the following tasks:

=over 2

=item * Call the superclass C<pack> method.

=item * Perform the guts of the pack

=item * Renumber the C<Messages> member of $self.

=item * Do not forget to update C<current_message> based on the renumbering.

=back

=cut

sub pack { return 1; }

###############################################################################

=head2 get_message($msg_number)

Retrieve a C<Mail::Internet> reference to specified C<$msg_number>.
The base class method will return C<0> if a folder has not been opened
in the object or if the specified C<$msg_number> does not exist.

If present, it removes the C<Content-Length> field from the message
reference that it returns.

It also caches the header just like C<get_header> does.

The folder interface is expected to perform the following tasks:

=over 2

=item * Call the superclass C<get_message> method.

=item * Extract the message into a C<Mail::Internet> object.

=back

=cut

sub get_message {
  return((($_[0]->foldername ne '') &&
	  defined($_[0]->{Messages}{$_[1]})) ? 1 : 0);
}

=head2 get_mime_message($msg_number [, parserobject] [, %options])

Retrieves a C<MIME::Entity> reference for the specified
C<$msg_number>.  Returns C<undef> on failure.

It essentially calls C<get_message_file> to get a file to parse,
creates a C<MIME::Parser> object, configures it a little, and then
calls the C<MIME::Parser->read> method to create the C<MIME::Entity>
object.

If C<parserobject> is specified it will be used instead of an
internally created parser object.  The parser object is expected to a
class instance and a subcless (however far removed) of
C<MIME::ParserBase>.

Options are specified as hash items using key and value pairs.

Here is the list of known options.  They essentially map into the
C<MIME::Parser> methods of the same name.  For documentation regarding
these options, refer to the documentation for C<MIME::Parser>.

=over 2

=item * output_dir

=item * output_prefix

=item * output_to_core

=back

=cut

sub get_mime_message {
  my $self = shift;
  my $msg = shift;
  my $parser;

  if ($_[0]->is_instance) {
    $_[0]->class('MIME::ParserBase')
      or croak "$_[0] isn't a subclass of MIME::ParserBase";
    $parser = shift;
  }
  my %options = @_;

  $parser ||= new MIME::Parser or return undef;
  my $file = $self->get_message_file($msg) or return undef;

  !defined($options{'output_dir'})
    or $parser->output_dir($options{'output_dir'})
      or return undef;
  !defined($options{'output_prefix'})
    or $parser->output_prefix($options{'output_prefix'})
      or return undef;
  !defined($options{'output_to_core'})
    or $parser->output_to_core($options{'output_to_core'})
      or return undef;

  my $fh = new IO::File $file
    or croak "can't open $file: $!";
  my $entity = $parser->read($fh);
  $fh->close;

  return $entity;
}

=head2 get_message_file($msg_number)

Acts like C<get_message()> except that a filename is returned instead
of a B<Mail::Internet> object reference.  This might be useful for
dealing with the B<MIME-tools> package.

Please note that C<get_message_file> does NOT perform any 'From '
escaping or unescaping regardless of the underlying folder
architecture.  I am working on a mechanism that will resolve any
resulting issues with this malfeature.

The folder interface is expected to perform the following tasks:

=over 2

=item * Call the superclass C<get_message_file> method.

=item * Extract the message into a temp file (if not already in one)
and return the name of the file.

=back

=cut

sub get_message_file {
  return((($_[0]->foldername ne '') &&
	  defined($_[0]->{Messages}{$_[1]})) ? 1 : 0);
}

=head2 get_header($msg_number)

Retrieves a message header.  Returns a reference to a B<Mail::Header>
object.  It caches the result for later use.

The folder interface is expected to perform the following tasks:

=over 2

=item * Call the superclass C<get_header> method.

=item * Return the cached entry if it exists.

=item * Extract the header into a C<Mail::Internet> object.

=item * Cache it.

=back

=cut

sub get_header {
  return((($_[0]->foldername ne '') &&
	  defined($_[0]->{Messages}{$_[1]})) ? 1 : 0);
}

=head2 get_mime_header($msg_number)

Retrieves the message header for the given message and returns a
reference to C<MIME::Head> object.  It actually calls C<get_header>,
creates a C<MIME::Head> object, then stuffs the contents of the
C<Mail::Header> object into the C<MIME::Head> object.

=cut

sub get_mime_header {
  my $self = shift;
  my $msg = shift;
  my $href = $self->get_header($msg);
  my $mime_href = new MIME::Head(Modify => 0,
				 MailFrom => 'COERCE')
    or croak "can't create MIME::Head: $!";
  $mime_href->header($href->header) or return undef;
  return $mime_href;
}

###############################################################################

=head2 append_message($mref)

Add a message to a folder.  Given a reference to a B<Mail::Internet>
object, append it to the end of the folder.  The result is not
committed to the original folder until a C<sync> is performed.

The C<Content-Length> field is added to the written file if the
C<Content-Length> option is enabled.


This method will, under certain circumstances, alter the message
reference that was passed to it.  If you are writing a folder
interface, make sure you pass a dup of the message reference when
calling the SUPER of the method.  For examples, see the code for the
stock folder interfaces provided with Mail::Folder.

=cut

sub append_message {
  my $self = shift;
  my $mref = shift;

  return 0 if ($self->foldername eq '');
  $self->_update_content_length($mref);
  return 1;
}

=head2 update_message($msg_number, $mref)

Replaces the message identified by C<$msg_number> with the contents of
the message in reference to a B<Mail::Internet> object C<$mref>.
The result is not committed to the original folder until a C<sync> is
performed.

This method will, under certain circumstances, alter the message
reference that was passed to it.  If you are writing a folder
interface, make sure you pass a dup of the message reference when
calling the SUPER of the method.  For examples, see the code for the
stock folder interfaces provided with Mail::Folder.

The folder interface is expected to perform the following tasks:

=over 2

=item * Call the superclass C<update_message> method.

=item * Replace the specified message in the working copy of the folder.

=back

=cut

sub update_message {
  my $self = shift;
  my $key = shift;
  my $mref = shift;

  return 0 if (($self->foldername eq '') ||
	       !defined($self->{Messages}{$key}));

  $self->invalidate_header($key);
  $self->_update_content_length($mref) if $self->get_option('Content-Length');
  $self->add_label($key, 'edited');
  return 1;
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
  
  my $mref = $self->get_message($msg);
  
  return 0 if (!$mref ||
	       !$folder->append_message($mref) ||
	       !$self->delete_message($msg));

  return 1;
}

=head2 dup($msg_number, $folder_ref)

Copies a message to a folder.  Works like C<refile>, but does not
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

=head2 delete_message(@msg_numbers)

Mark a list of messages for deletion.  The actual delete in the
original folder is not performed until a C<sync> is performed.  This
is merely a convenience wrapper around C<add_label>.  It returns C<1>.

If any of the items in C<@msg_numbers> are array references,
C<delete_message> will expand out the array reference(s) and call
C<add_label> for each of the items in the reference(s).

=cut

sub delete_message {
  my $self = shift;
  my @keys = @_;
  
  for my $key (@keys) {
    if (ref($key) eq 'ARRAY') {
      for my $key2 (@{$key}) {
	$self->add_label($key2, 'deleted')
	  if defined($self->{Messages}{$key2});
      }
    } else {
      $self->add_label($key, 'deleted') if defined($self->{Messages}{$key});
    }
  }
  return 1;
}

=head2 undelete_message(@msg_numbers)

Unmarks a list of messages marked for deletion.  This is merely a
convenience wrapper around C<delete_label>.  It returns C<1>.

If any of the items in C<@msg_numbers> are array references,
C<undelete_message> will expand out the array reference(s) and call
C<delete_label> for each of the items in the reference(s).

=cut

sub undelete_message {
  my $self = shift;
  my @keys = @_;

  for my $key (@keys) {
    if (ref($key) eq 'ARRAY') {
      for my $key2 (@{$key}) {
	$self->delete_label($key2, 'deleted')
	  if defined($self->{Messages}{$key2});
      }
    } else {
      $self->delete_label($key, 'deleted')
	if defined($self->{Messages}{$key});
    }
  }
  return 1;
}

=head2 message_list

Returns a list of the message numbers in the folder.  The list is not
guaranteed to be in any specific order.

=cut

sub message_list { return(keys %{$_[0]->{Messages}}); }

=head2 qty

Returns the quantity of messages in the folder.

=cut

sub qty { return(scalar keys %{$_[0]->{Messages}}); }

###############################################################################

=head2 first_message

Returns the message number of the first message in the folder.

=cut

sub first_message {
  my @message_list = sort { $a <=> $b } $_[0]->message_list;

  return 0 if ($#message_list == -1);
  return shift(@message_list);
}

=head2 last_message

Returns the message number of the last message in the folder.

=cut

sub last_message {
  my @message_list = sort { $a <=> $b } $_[0]->message_list;

  return 0 if ($#message_list == -1);
  return pop(@message_list);
}

=head2 next_message

=head2 next_message($msg_number)

Returns the message number of the next message in the folder relative
to C<$msg_number>.  If C<$msg_number> is not specified then the
message number of the next message relative to the current message is
returned.  It returns C<0> if there is no next message (ie. at the end
of the folder).

=cut

sub next_message {
  my $self = shift;
  my $msg_number = shift;

  $msg_number = $self->current_message unless (defined($msg_number));
  my $last_message = $self->last_message;

  while (++$msg_number <= $last_message) {
    return $msg_number if (defined($self->{Messages}{$msg_number}));
  }
  return 0;
}

=head2 prev_message

=head2 prev_message($msg_number)

Returns the message number of the previous message in the folder
relative to C<$msg_number>.  If C<$msg_number> is not specified then
the message number of the next message relative to the current message
is returned.  It returns C<0> is there is no previous message (ie. at
the beginning of the folder).

=cut

sub prev_message {
  my $self = shift;
  my $msg_number = shift;
  
  $msg_number = $self->current_message unless (defined($msg_number));
  my $first_message = $self->first_message;

  while (--$msg_number >= $first_message) {
    return $msg_number if (defined($self->{Messages}{$msg_number}));
  }
  return 0;
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

  for my $msg (sort { $a <=> $b } $self->message_list) {
    return $msg if ($self->label_exists($msg, $label));
  }
  return 0;
}

=head2 last_labeled_message($label)

Returns the message number of the last message in the folder that has
the label C<$label> associated with it.  Returns C<0> if there are no
messages with the given label.

=cut

sub last_labeled_message {
  my $self = shift;
  my $label = shift;

  for my $msg (sort { $b <=> $a } $self->message_list) {
    return $msg if ($self->label_exists($msg, $label));
  }
  return 0;
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
  return 0;
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
  return 0;
}

###############################################################################

=head2 current_message

=head2 current_message($msg_number)

When called with no arguments returns the message number of the
current message in the folder.  When called with an argument set the
current message number for the folder to the value of the argument.

For folder mechanisms that provide persistant storage of the current
message, the underlying folder interface will update that storage.
For those that do not, changes to C<current_message> will be affect
while the folder is open.

=cut

sub current_message {
  my $self = shift;
  my $key = shift;

  return $self->{Current} if (!defined($key));

  return($self->{Current} = $key);
}

###############################################################################

=head2 sort($func_ref)

Returns a sorted list of messages.  It works conceptually similar to
the regular perl C<sort>.  The C<$func_ref> that is passed to C<sort>
must be a reference to a function.  The function will be passed two
B<MIME::Head> message references and it must return an integer less
than, equal to, or greater than 0, depending on how the list is to be
ordered.

=cut

sub sort {
  my $self = shift;
  my $sort_func_ref = shift;

  return sort {&$sort_func_ref($self->get_header($a),
			       $self->get_header($b))} $self->message_list;
}

=head2 select($func_ref)

Returns a list of message numbers that match a set of criteria.  The
method is passed a reference to a function that is used to determine
the match criteria.  The function will be passed a reference to a
B<Mail::Internet> message object containing only a header.

The list of message numbers returned is not guaranteed to be in any
specific order.

=cut

sub select {
  my $self = shift;
  my $select_func_ref = shift;

  return grep(&{$select_func_ref}($self->get_header($_)),
	      $self->message_list);
}

=head2 inverse_select($func_ref)

Returns a list of message numbers that do not match a set of criteria.
The method is passed a reference to a function that is used to
determine the match criteria.  The function will be passed a reference
to a B<Mail::Internet> message object containing only a header.

The list of message numbers returned is not guarenteed to be in any
specific order.

=cut

sub inverse_select {
  my $self = shift;
  my $select_func_ref = shift;

  return grep(!&{$select_func_ref}($self->get_header($_)),
	      $self->message_list);
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
interface, rather they represent a standard set of labels for MUAs to
use.

=over 2

=item * deleted

This is used by the C<delete_message> and C<sync> to process the
deletion of messages.  These will not be reflected in any persistant
storage of message labels.

=item * edited

This tag is added by C<update_message> to reflect that the message has
been altered.  This behaviour may go away.

=item * seen

This means that the message has been viewed by the user.  The concept
of C<seen> is nebulous at best.  The C<get_message> method sets this
label for any message it is asked to retrieve.

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

  return 0 if (!length($label));
  $self->{Messages}{$msg_number}{Labels}{$label}++;
  return 1;
}

=head2 delete_label($msg_number, $label)

Deletes the association of C<$label> with C<$msg_number>.

Returns C<0> if the label C<$label> was not associated with
C<$msg_number>, otherwise returns a C<1>.

=cut

sub delete_label {
  my $self = shift;
  my $msg_number = shift;
  my $label = shift;

  return 0 if (!defined($self->{Messages}{$msg_number}{Labels}) ||
	       !defined($self->{Messages}{$msg_number}{Labels}{$label}));

  delete $self->{Messages}{$msg_number}{Labels}{$label};
  return 1;
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

  for my $msg (keys %{$self->{Messages}}) {
    $qty += $self->delete_label($msg, $label);
  }
  return $qty;
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

If C<list_labels> is called in a scalar context, it returns the
quantity of labels that are associated with C<$msg_number>.

The returned list is not guaranteed to be in any specific order.

=cut

sub list_labels {
  my $self = shift;
  my $msg_number = shift;
  my @msgs = ();

  if (defined($self->{Messages}{$msg_number}{Labels})) {
    @msgs = keys %{$self->{Messages}{$msg_number}{Labels}}
  }
  return(wantarray ? @msgs : scalar @msgs);
}

=head2 list_all_labels

Returns a list of all the labels that are associated with the messages
in the folder.  The items in the returned list are not guaranteed to
be in any particular order.

If C<list_all_labels> is called in a scalar context, it returns the
quantity of labels that are associated with the messages.

=cut

sub list_all_labels {
  my $self = shift;
  my %alllabels;
  my @msgs;

  for my $msg (keys %{$self->{Messages}}) {
    for my $label ($self->list_labels($msg)) {
      $alllabels{$label}++;
    }
  }
  @msgs = keys %alllabels;
  return(wantarray ? @msgs : scalar @msgs);
}

=head2 select_label($label)

Returns a list of message numbers that have the given label C<$label>
associated with them.

If C<select_label> is called in a scalar context, it will return the
quantity of message that have the given label.

=cut

sub select_label {
  my $self = shift;
  my $label = shift;
  my @msgs;

  for my $msg (keys %{$self->{Messages}}) {
    push(@msgs, $msg) if (defined($self->{Messages}{$msg}{Labels}) &&
			  defined($self->{Messages}{$msg}{Labels}{$label}));
  }
  return(wantarray ? @msgs : scalar @msgs);
}

###############################################################################

=head2 foldername

Returns the name of the folder that the object has open.

=cut

sub foldername { return $_[0]->{Name}; }

=head2 message_exists($msg_number)

Returns C<1> if the folder object contains a reference for
C<$msg_number>, otherwise returns C<0>.

=cut

sub message_exists { return defined($_[0]->{Messages}{$_[1]}); }

=head2 set_readonly

Sets the C<readonly> attribute for the folder.  This will cause the
C<sync> command to not perform any updates to the actual folder.

=cut

sub set_readonly { $_[0]->{Readonly} = 1; }

=head2 is_readonly

Returns C<1> if the C<readonly> attribute for the folder is set,
otherwise returns C<0>.

=cut

sub is_readonly { return $_[0]->{Readonly}; }

=head2 get_option($option)

Returns the setting for the given option.  Returns C<undef> if the
option does not exist.

=cut

sub get_option {
  my $self = shift;
  my $option = shift;

  return undef if (!defined($self->{Options}{$option}));
  return $self->{Options}{$option};
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

=head2 debug($value)

Set the level of debug information for the object.  If C<$value> is
not given then the current debug level is returned.

=cut

sub debug {
  my $self = shift;
  my $level = shift;

  my $pkg = ref($self);
  my $oldval = $self->{Debug} || 0;

  return $oldval if (!defined($level));

  $self->{Debug} = $level;

  return $oldval;
}

=head2 debug_print($text)

Outputs $text, along with some other information to STDERR.  The
format of the outputted line is as follows:

C<-<gt> $subroutine $self $text>

=cut

sub debug_print {
  my $self = shift;
  my $text = shift;

  my $pkg = ref($self) || $self;
  my ($package, $filename, $line, $subroutine) = caller(1);

  print(STDERR "-> $subroutine $self $text\n");
}

###############################################################################

=head1 WRITING A FOLDER INTERFACE

=head2 General Concepts

In general, writing a folder interface consists of writing a set of
methods that overload some of the native ones in C<Mail::Folder>.
Below is a list of the methods that will typically need to overridden.
See the code of the folder interfaces provided with the package for
specific examples.

Basically, the goal of an interface writer is to map the mechanics of
interfacing to the folder format into the methods provided by the base
class.  If there are any obvious additions to be made, let me know.
If it looks like I can fit them in and they make sense in the larger
picture, I will add them.

If you set about writing a folder interface and find that something is
missing from this documentation, please let me know.

=head2 Initialization

The beginning of a new folder interface module should start with
something like the following chunk of code:

    package Mail::Folder::YOUR_FOLDER_TYPE;
    @ISA = qw(Mail::Folder);
    use Mail::Folder;

    Mail::Folder::register_folder_type('Mail::Folder::YOUR_FOLDER_TYPE',
				       'your_folder_type_name');

=head2 Envelopes

Please take note that inter-folder envelope issues are not complete
ironed out yet.  Some folder types (maildir via qmail) actually store
all of the envelope information, some (mbox) only store a portion of
it, and others do not store any.  Electronic has a rich history of
various issues related this issue (anyone out there remember the days
when many elm programs were compiled to use the 'C<From_>' field for
replies instead of the fields in the actual header - and then everyone
started do non-uucp email? :-).

Depending on the expectations, the scale of the problem is relative.
Here is what I have done so far to deal with the problem.

In the stock folder interfaces, the underlying Mail::Internet object
is created with the 'C<MailFrom>' option set to 'C<COERCE>'.  This
will cause it to rename a 'C<From_>' field to a 'C<Mail-From>' field.
All interface writers should do the same.  This will prevent the
interface writer from needing to deal with it themselves.

For folder interfaces that require part or all of the envelope to be
present as part of the stored message, then coercion is sometimes
necessary.  As an example, the C<maildir> folder format uses a
'C<Return-Path>' field as the first line in the file to signify the
sender portion of the envelope.  If that field is not present, then
the interfaces tries to synthesize it by way of the 'C<Reply-To>',
'C<From>', and 'C<Sender>' fields (in that order).  Currently, it
croaks if it fails that sequence of fields (this will probably change
in the future - feedback please).  At some time in the future, I am
going to try to provide some generalized routines to perform these
processes in a consistant manner across all of the interfaces; in the
mean time, keep an eye out for issues related to this whole mess.

Every folder interface should take to prevent some of the more common
problems like being passed in a message with a 'C<From_>' field.  If
all other fields that carry similar information are present, then
delete the field.  If the interface can benefit from coercing it into
another field that would otherwise be missing, go for it.  Even if all
of the other interfaces do the right thing, a user might hand it a
mail message that contains a 'C<From_>' field, so one cannot be to
careful.

The recipient portion of the envelope is pretty much not dealt with at
all.  If it presents any major issues, describe them to me and I will
try to work something out.

=head2 Methods to override

The following methods will typically need to be overridden in the
folder interface.

=over 2

=item * open

=item * close

=item * sync

=item * pack

=item * get_header

=item * get_message

=item * get_message_file

=item * update_message

=back

=head1 FOLDER INTERFACE METHODS

This section describes the methods that for use by interface writers.
Refer to the stock folder interfaces for examples of their use.

=head2 register_folder_type($class, $type)

Registers a folder interface with Mail::Folder.

=cut

sub register_folder_type { $folder_types{$_[1]} = $_[0]; }

=head2 is_valid_folder_format($foldername)

In a folder interface, this method should return C<1> if it thinks the
folder is valid format and return C<0> otherwise.  It is used by the
Mail::Folder C<open> method when C<AUTODETECT> is used as the folder
type.  The C<open> method iterates through the list of known folder
interfaces until it finds one that answer yes to the question.

This method is always overrided by the folder interface.

=cut

sub is_valid_folder_format { return 0; }

=head2 init

This is a stub entry called by C<new>.  The primary purpose is to
provide a method for subclasses to override for initialization to be
performed at constructor time.  It is called after the object members
variables have been initialized and before the optional call to
C<open>.  The C<new> method will return C<undef> if the C<init> method
returns C<0>.  Only interface writers need to worry about this one.

=cut

sub init { return 1; }

=head2 create($foldername)

In a folder interface, this method should return C<1> after it
successfully creates a folder with the given name and return C<0>
otherwise.

This method is always overrided by the folder interface.  The base
class method returns a C<0> so that if C<create> is not defined in the
folder interface, the call to C<create> will return failure.

=cut

sub create { return 0; }

=head2 cache_header($msg_number, $header_ref)

Associates C<$header_ref> with C<$msg_number> in the internal header
cache of the object.

=cut

sub cache_header { $_[0]->{Messages}{$_[1]}{Header} = $_[2]; }

=head2 invalidate_header($msg_number)

Clobbers the header cache entry for C<$msg_number>.

=cut

sub invalidate_header { delete $_[0]->{Messages}{$_[1]}{Header}; }

=head2 remember_message($msg_number)

Add an entry for C<$msg_number> to the internal data structure of the
folder object.

=cut

sub remember_message {
  if (!defined($_[0]->{Messages}{$_[1]})) {
    $_[0]->{Messages}{$_[1]} = {};
    $_[0]->{Messages}{$_[1]}{Header} = undef;
  }
}

=head2 forget_message($msg_number)

Removes the entry for C<$msg_number> from the internal data structure
of the folder object.

=cut

sub forget_message {
  delete $_[0]->{Messages}{$_[1]};
  print("arf $_[1]\n") if exists($_[0]->{Messages}{$_[1]});
}

###############################################################################

sub _detect_folder_type {
  my $folder = shift;

  for my $type (sort keys %folder_types) {
    return $type
      if (eval "$folder_types{$type}::is_valid_folder_format(\"$folder\")");
  }
}

sub _update_content_length {
  my $self = shift;
  my $mref = shift;

  return 0 unless $self->get_option('Content-Length');

  my $content_length = $#{$mref->body} + 1;

  if ($mref->head->count('Content-Length')) {
    $mref->head->replace('Content-Length', $content_length);
  } else {
    $mref->head->add('Content-Length', $content_length);
  }
  return $content_length;
}

###############################################################################

=head1 CAVEATS

If a script forks while having any folders open, only the parent
should make any changes to the folder.  In addition, when the parent
closes the folder, related temporary files will be reaped.  This
temporary file cleanup will not occur for the child.  I am
contemplating a more general solution to this problem, but until then
B<ONLY PARENTS SHOULD MANIPULATE MAIL>.

=head1 AUTHOR

Kevin Johnson E<lt>F<kjj@pobox.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 1996-1997 Kevin Johnson <kjj@pobox.com>.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
