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

print "1..12\n";

okay_if(1, Mail::Folder::register_folder_type(Mail::Folder::Emaul, 'emaul'));
okay_if(2, $folder = new Mail::Folder('emaul', "testfolders/emaul_1"));
okay_if(3, !$folder->refile(2, $folder));
okay_if(4, $folder->refile(1, $folder));
okay_if(5, (-e "testfolders/emaul_1/1"));
okay_if(6, (-e "testfolders/emaul_1/3"));
okay_if(7, (-e "testfolders/emaul_1/4"));
okay_if(8, ($folder->sync() == 0));
okay_if(9, !(-e "testfolders/emaul_1/1"));
okay_if(10, (-e "testfolders/emaul_1/3"));
okay_if(11, (-e "testfolders/emaul_1/4"));
okay_if(12, $folder->close());

1;
