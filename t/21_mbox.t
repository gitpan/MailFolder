#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Mbox;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink('testfolders/mbox_1');
system("cp testfolders/mbox_seed testfolders/mbox_1");

print "1..2\n";

okay_if(1, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
okay_if(2, $folder->close);

1;
