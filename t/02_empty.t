#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder;
use Mail::Folder::Emaul;
use Mail::Internet;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

for $dir (qw(testfolders)) {
  (-e $dir) || die("$dir doesn't exist\n");
  (-d $dir) || die("$dir isn't a directory\n");
  (-r $dir) || die("dir isn't readable\n");
}
system("rm -rf testfolders/emaul_empty");
system("mkdir testfolders/emaul_empty");

print "1..8\n";

okay_if(1, Mail::Folder::register_folder_type(Mail::Folder::Emaul, 'emaul'));
okay_if(2, $folder = new Mail::Folder('emaul'));

okay_if(3, ($folder->sync() == -1)); # folder isn't open
okay_if(4, $folder->open("testfolders/emaul_empty"));
@msgs = $folder->message_list();
okay_if(5, ($#msgs == -1));	# folder is empty
okay_if(6, !$folder->sync());	# no additions to the folder
okay_if(7, $folder->close());
@deletes = (keys %{$folder->{Deletes}});
okay_if(8, ($#deletes == -1));	# make sure the close closed up shop

1;
