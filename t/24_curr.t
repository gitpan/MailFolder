#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Mbox;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink('testfolders/mbox_1');
system("cp testfolders/mbox_seed testfolders/mbox_1");

print "1..10\n";

okay_if(1, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));

@msgs = $folder->message_list;
okay_if(2, ($#msgs == 1));	# correct number of messages?
okay_if(3, ($folder->current_message == 1));
okay_if(4, (($next_message = $folder->next_message(1)) == 2));
okay_if(5, ($folder->current_message($next_message)));
okay_if(6, ($folder->current_message == 2));
okay_if(7, ($folder->prev_message(2) == 1));
okay_if(8, ($folder->first_message == 1));
okay_if(9, ($folder->last_message == 2));

okay_if(10, $folder->close);

1;
