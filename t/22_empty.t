#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder;
use Mail::Folder::Mbox;
use Mail::Internet;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink("testfolders/mbox_empty");
(! -e "testfolders/mbox_empty") ||
  die("can't unlink testfolders/mbox_empty: $!\n");
system("touch testfolders/mbox_empty");
(-e "testfolders/mbox_empty") ||
  die("can't create testfolders/mbox_empty: $!\n");

print "1..8\n";

okay_if(1, Mail::Folder::register_folder_type(Mail::Folder::Mbox, 'mbox'));
okay_if(2, $folder = new Mail::Folder('mbox'));

okay_if(3, ($folder->sync() == -1)); # folder isn't open
okay_if(4, $folder->open("testfolders/mbox_empty"));
@msgs = $folder->message_list();
okay_if(5, ($#msgs == -1));	# folder is empty
okay_if(6, !$folder->sync());	# no additions to the folder
okay_if(7, $folder->close());
@deletes = (keys %{$folder->{Deletes}});
okay_if(8, ($#deletes == -1));	# make sure the close closed up shop

1;
