#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Mbox;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink('testfolders/mbox_1');
system("cp testfolders/mbox_seed testfolders/mbox_1");

print "1..9\n";

okay_if(1, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));

okay_if(2, (@msgs = $folder->message_list));
okay_if(3,
	$folder->current_message($folder->next_message($folder->current_message)));
okay_if(4, ($folder->pack));	# no-op - ie. 1,2 -> 1,2
okay_if(5, (@msgs = $folder->message_list));
okay_if(6, ($msgs[0] == 1));
okay_if(7, ($msgs[1] == 2));
okay_if(8, ($folder->current_message == 2));

okay_if(9, $folder->close);

1;
