#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Mbox;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink('testfolders/mbox_1');
system("cp testfolders/mbox_seed testfolders/mbox_1");
chmod(0644, 'testfolders/mbox_1');

print "1..8\n";

okay_if(1, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));

okay_if(2, !$folder->delete_message(999)); # try to delete non-existant one
okay_if(3, $folder->delete_message(2)); # try to delete an existing one
okay_if(4, $folder->sync == 0);
okay_if(5, $folder->close);

okay_if(6, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
@msgs = $folder->message_list;
okay_if(7, $#msgs == 0);
okay_if(8, $folder->close);

1;
