#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder;
use Mail::Folder::Mbox;
use Mail::Internet;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

system("cp testfolders/mbox_seed testfolders/mbox_1");

print "1..11\n";

okay_if(1, Mail::Folder::register_folder_type(Mail::Folder::Mbox, 'mbox'));
okay_if(2, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
okay_if(3, ($message = $folder->get_message(1)));
okay_if(4, ($message->replace('subject', 'zoink')));
okay_if(5, $folder->update_message(1, $message));
okay_if(6, $folder->sync() == 0);
okay_if(7, $folder->close());

okay_if(8, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
okay_if(9, $message = $folder->get_header(1));
okay_if(10, $message->get('subject') eq "zoink\n");
okay_if(11, $folder->close());

1;
