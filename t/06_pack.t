#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder;
use Mail::Folder::Emaul;
use Mail::Internet;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

for $dir (qw(testfolders testfolders/emaul_seed)) {
  (-e $dir) || die("$dir doesn't exist\n");
  (-d $dir) || die("$dir isn't a directory\n");
  (-r $dir) || die("dir isn't readable\n");
}
system("rm -rf testfolders/emaul_1");
system("mkdir testfolders/emaul_1");
system("cp testfolders/emaul_seed/* testfolders/emaul_1");
system("echo 1 >testfolders/emaul_1/.current_msg");

print "1..16\n";

okay_if(1, Mail::Folder::register_folder_type(Mail::Folder::Emaul, 'emaul'));
okay_if(2, $folder = new Mail::Folder('emaul', "testfolders/emaul_1"));

okay_if(3, (@msgs = $folder->message_list()));
okay_if(4, ($#msgs == 1));
okay_if(5, ($msgs[0] == 1));
okay_if(6, ($msgs[1] == 3));
okay_if(7, $folder->current_message($folder->next_message));
okay_if(8, ($folder->pack()));	# 1,3 -> 1,2
okay_if(9, (@msgs = $folder->message_list()));
okay_if(10, ($msgs[0] == 1));
okay_if(11, ($msgs[1] == 2));
okay_if(12, (-e "testfolders/emaul_1/$msgs[0]"));
okay_if(13, (-e "testfolders/emaul_1/$msgs[1]"));
okay_if(14, !(-e "testfolders/emaul_1/3"));
okay_if(15, ($folder->current_message() == 2));

okay_if(16, $folder->close());

1;