#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder;
use Mail::Folder::Mbox;
use Mail::Internet;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

system("cp testfolders/mbox_seed testfolders/mbox_1");

print "1..9\n";

okay_if(1, Mail::Folder::register_folder_type(Mail::Folder::Mbox, 'mbox'));
okay_if(2, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));

okay_if(3, !$folder->delete_message(999)); # try to delete non-existant one
okay_if(4, $folder->delete_message(2)); # try to delete an existing one
okay_if(5, ($folder->sync() == 0));
okay_if(6, $folder->close());

okay_if(7, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
@msgs = $folder->message_list();
okay_if(8, ($#msgs == 0));
okay_if(9, $folder->close());

1;
