#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Mbox;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink('testfolders/mbox_1');
system('cp testfolders/mbox_seed testfolders/mbox_1');
chmod(0600, 'testfolders/mbox_1');

print "1..14\n";

okay_if(1, $folder = new Mail::Folder('mbox', 'testfolders/mbox_1'));
@statary = stat('testfolders/mbox_1');
okay_if(2, ($statary[2] & 0777) == 0600);

system('cat testfolders/mbox_seed >>testfolders/mbox_1');
okay_if(3, ($folder->sync == 2));
@statary = stat('testfolders/mbox_1');
okay_if(4, ($statary[2] & 0777) == 0600);
@msgs = $folder->message_list;
okay_if(5, ($#msgs == 3));

okay_if(6, $folder->close);

chmod(0444, 'testfolders/mbox_1');
okay_if(7, $folder->open('testfolders/mbox_1'));
okay_if(8, $folder->is_readonly);
okay_if(9, $folder->delete_message(4));
okay_if(10, $folder->sync == 0);
okay_if(11, $folder->close);
okay_if(12, $folder->open('testfolders/mbox_1'));
okay_if(13, $folder->message_exists(4));
okay_if(14, $folder->close);

1;
