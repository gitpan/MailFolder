#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Mbox;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink("testfolders/mbox_empty");
(! -e "testfolders/mbox_empty") ||
  die("can't unlink testfolders/mbox_empty: $!\n");

print "1..5\n";

okay_if(1, $folder = new Mail::Folder('mbox',
				      'testfolders/mbox_empty',
				      Create => 1));

@msgs = $folder->message_list;
okay_if(2, ($#msgs == -1));	# folder is empty
okay_if(3, !$folder->sync);	# no additions to the folder
okay_if(4, $folder->close);
@deletes = (keys %{$folder->{Deletes}});
okay_if(5, ($#deletes == -1));	# make sure the close closed up shop

1;
