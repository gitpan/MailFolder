#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder;
use Mail::Folder::Mbox;
use Mail::Internet;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

system("cp testfolders/mbox_seed testfolders/mbox_1");
chmod(0600, "testfolders/mbox_1");

print "1..7\n";

okay_if(1, Mail::Folder::register_folder_type(Mail::Folder::Mbox, 'mbox'));
okay_if(2, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
@statary = stat("testfolders/mbox_1");
okay_if(3, ($statary[2] & 0777) == 0600);

system("cat testfolders/mbox_seed >>testfolders/mbox_1");
okay_if(4, ($folder->sync() == 2));
@statary = stat("testfolders/mbox_1");
okay_if(5, ($statary[2] & 0777) == 0600);
@msgs = $folder->message_list();
okay_if(6, ($#msgs == 3));

okay_if(7, $folder->close());

1;
