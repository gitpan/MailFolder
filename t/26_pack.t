#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder;
use Mail::Folder::Mbox;
use Mail::Internet;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

system("cp testfolders/mbox_seed testfolders/mbox_1");

print "1..10\n";

okay_if(1, Mail::Folder::register_folder_type(Mail::Folder::Mbox, 'mbox'));
okay_if(2, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));

okay_if(3, (@msgs = $folder->message_list()));
okay_if(4, $folder->current_message($folder->next_message));
okay_if(5, ($folder->pack()));	# no-op - ie. 1,2 -> 1,2
okay_if(6, (@msgs = $folder->message_list()));
okay_if(7, ($msgs[0] == 1));
okay_if(8, ($msgs[1] == 2));
okay_if(9, ($folder->current_message() == 2));

okay_if(10, $folder->close());

1;
