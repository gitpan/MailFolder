# -*-perl-*-
#
# Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.
#
# All rights reserved. This program is free software; you can
# redistribute it and/or modify it under the same terms as Perl
# itself.

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

For a specific example of adding a folder interface see
L<Mail::Folder::Emaul>.  More detailed documentation on the subject is
forthcoming.

=head1 ABSTRACT METHODS

These are the methods that a folder interface will override to perform
it's work on a folder.  The corresponding subclass methods should call
these methods if the call fails.

=cut

use Carp;
use vars qw(%folder_types, $VERSION);

%folder_types = {};

$VERSION = "0.01";

=head2 new()

=head2 new($folder_name)

Create a new, empty B<Mail::Folder> object.  If B<$folder_name> is
included, then the B<open> method is also called with that argument.

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
  $self->{Filename} = '';
  $self->{Deletes} = {};
  
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
does not perform an implicit B<sync>.  Make sure you so a B<sync>
before the B<close> if you want deletes and the like to be reflected
in the folder.

=cut

sub close {
  my $self = shift;
  
  $self->{Filename} = '';
  $self->{Messages} = {};
  $self->clear_deletes();
  
  return(1);
}

=head2 sync()

Synchronize the folder with the internal data structures.  The folder
interface will process deletes and read in any new messages that have
arrived in the folder since the last time it was either B<open>ed or
B<sync>ed.

=cut

sub sync {
  my $self = shift;

  return(($self->foldername() eq '') ? -1 : 0);
}

=head2 pack()

For folder formats like mh this will rename the files in the folder so
that there are no gaps in the message number sequence.  For other
folder formats (like mbox) it does nothing.

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
object, append it to the end of the folder.  Please note that this
operation takes place immediately, not during a B<sync>.

=cut

sub append_message {
  my $self = shift;
  my $mref = shift;
  
  return($self->foldername ne '');
}

=head2 update_message($msg_number, $message_ref)

Replaces the message identified by B<$msg_number> with the contents of
the message in reference to a B<Mail::Internet> object $message_ref.
Please note that this operation takes place immediately, not during a
B<sync>.

=cut

sub update_message {
  my $self = shift;
  my $key = shift;
  my $mref = shift;
  
  return($self->foldername ne '');
}
###############################################################################
=back

=head1 Class Methods

These methods are provided by the base class and probably don't need
to be overridden by a folder interface.

=head2 delete_message($msg_number)

Mark a message for deletion.  The actual deletion will be done by the
B<sync> method.

=cut

sub delete_message {
  my $self = shift;
  my $key = shift;
  
  return(0) if (!defined($self->{Messages}{$key}));

  $self->{Deletes}{$key} = $key;
  $self->forget_message($key);
  return(1);
}

=head2 message_list()

Returns a list of the message numbers in the folder.

=cut

sub message_list {
  my $self = shift;
  
  return(sort {$a <=> $b} keys %{$self->{Messages}});
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

Based on the current message number, returns the message number of the
next message in the folder.

=cut

sub next_message {
  my $self = shift;
  
  my(@messages) = $self->message_list();
  my($curr_message) = $self->current_message();
  my($message);
  
  foreach $message (@messages) {
    return $message if ($message > $curr_message);
  }
  return(-1);
}

=head2 prev_message()

Based on the current message number, returns the message number of the
previous message in the folder.

=cut

sub prev_message {
  my $self = shift;
  
  my(@messages) = $self->message_list();
  my($curr_message) = $self->current_message();
  my($message);
  
  foreach $message (sort {$b <=> $a} @messages) {
    return $message if ($message < $curr_message);
  }
  return(-1);
}

=head2 current_message()

=head2 current_message($msg_number)

When called with no arguments returns the message number of the
current message in the folder.  When called with an argument set the
current message number for the folder to the value of the argument.

=cut

sub current_message {
  my $self = shift;
  my $key = shift;
  
  return($self->{Current}) if (!defined($key));

  $self->{Current} = $key;
  return(1);
}

=head2 sort($func_ref)

Returns a sorted list of messages.  The method is passed a reference
to a function that will accept two B<Mail::Internet> message
references containing only the headers and will return an integer less
than, equal to, or greater than 0, depending on how the elements of
the array are to be ordered.

=cut

sub sort {
  my $self = shift;
  my $sort_func_ref = shift;
  
  return(sort {&{$sort_func_ref}($self->get_header($a),
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
  
  my(@msgs, $msg);
  
  foreach $msg ($self->message_list()) {
    push(@msgs, $msg) if (&{$select_func_ref}($self->get_header($msg)));
  }
  
  return(@msgs);
}

=head2 refile($msg_number, $folder_ref)

Moves a message from one folder to another.

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
sub remember_message {
  my $self = shift;
  my $key = shift;
  my $value = shift;
  
  $self->{Messages}{$key} = $value;
}

sub forget_message {
  my $self = shift;
  my $key = shift;
  
  delete $self->{Messages}{$key};
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

=head1 AUTHOR

Kevin Johnson E<lt>F<kjj@primenet.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 1996 Kevin Johnson <kjj@primenet.com>.

All rights reserved. This program is free software; you can
redistribute it and/or modify it under the same terms as Perl itself.

=cut

1;
