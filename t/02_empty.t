#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Emaul;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

for $dir (qw(testfolders)) {
  (-e $dir) || die("$dir doesn't exist\n");
  (-d $dir) || die("$dir isn't a directory\n");
  (-r $dir) || die("dir isn't readable\n");
}
system("rm -rf testfolders/emaul_empty");

print "1..5\n";

okay_if(1, $folder = new Mail::Folder('emaul',
				      'testfolders/emaul_empty',
				      Create => 1));

@msgs = $folder->message_list;
okay_if(2, ($#msgs == -1));	# folder is empty
okay_if(3, !$folder->sync);	# no additions to the folder
okay_if(4, $folder->close);
@deletes = (keys %{$folder->{Deletes}});
okay_if(5, ($#deletes == -1));	# make sure the close closed up shop

1;
