#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Emaul;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

for $dir (qw(testfolders testfolders/emaul_seed)) {
  (-e $dir) || die("$dir doesn't exist\n");
  (-d $dir) || die("$dir isn't a directory\n");
  (-r $dir) || die("dir isn't readable\n");
}
chmod(0755, "testfolders/emaul_1");
system("rm -rf testfolders/emaul_1");
mkdir("testfolders/emaul_1", 0755);
system("cp testfolders/emaul_seed/[0-9] testfolders/emaul_1");
system("echo 1 >testfolders/emaul_1/.current_msg");

$select_nofind = sub {
  my($message) = shift;

  return($message->get('subject') eq 'wontfind');
};

$select_greeble = sub {
  my($message) = shift;

  return($message->get('subject') eq "greeble\n");
};

$select_all = sub {
  my($message1) = shift;
  my($message2) = shift;

  return(1);
};

print "1..8\n";

okay_if(1, $folder = new Mail::Folder('emaul', "testfolders/emaul_1"));
@msgs = $folder->select($select_nofind);
okay_if(2, ($#msgs == -1));
@msgs = $folder->select($select_all);
okay_if(3, ($#msgs == 1));
okay_if(4, ($msgs[0] == 1));
okay_if(5, ($msgs[1] == 3));
@msgs = $folder->select($select_greeble);
okay_if(6, ($#msgs == 0));
okay_if(7, ($msgs[0] == 3));
okay_if(8, $folder->close);

1;
