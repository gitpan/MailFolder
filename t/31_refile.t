#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Mbox;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink('testfolders/mbox_1');
system("cp testfolders/mbox_seed testfolders/mbox_1");
chmod(0644, 'testfolders/mbox_1');

print "1..14\n";

okay_if(1, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
okay_if(2, !$folder->refile(3, $folder));
okay_if(3, $folder->refile(1, $folder));
okay_if(4, $folder->dup(2, $folder));
okay_if(5, $message = $folder->get_header(4));
okay_if(6, ($message->get('subject') eq "greeble\n"));
okay_if(7, ($folder->sync == 0));
okay_if(8, $folder->close);

okay_if(9, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
@msgs = $folder->message_list;
okay_if(10, $#msgs == 2);
$message = $folder->get_header(1);
okay_if(11, $message->get('subject') eq "greeble\n");
$message = $folder->get_header(2);
okay_if(12, $message->get('subject') eq "arf\n");
$message = $folder->get_header(3);
okay_if(13, $message->get('subject') eq "greeble\n");
okay_if(14, $folder->close);

1;
