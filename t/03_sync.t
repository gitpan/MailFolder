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

print "1..5\n";

okay_if(1, Mail::Folder::register_folder_type(Mail::Folder::Emaul, 'emaul'));
okay_if(2, $folder = new Mail::Folder('emaul', "testfolders/emaul_1"));

system("cp testfolders/emaul_1/1 testfolders/emaul_1/4");
okay_if(3, ($folder->sync() == 1));
@msgs = $folder->message_list();
okay_if(4, ($#msgs == 2));

okay_if(5, $folder->close());

1;
