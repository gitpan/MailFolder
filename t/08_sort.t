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

$sort_spec = sub {
  my($message1) = shift;
  my($message2) = shift;

  return($message2->get('subject') cmp $message1->get('subject'));
};

print "1..4\n";

okay_if(1, $folder = new Mail::Folder('emaul', "testfolders/emaul_1"));
@msgs = $folder->sort($sort_spec);
okay_if(2, ($msgs[0] == 3));
okay_if(3, ($msgs[1] == 1));
okay_if(4, $folder->close);

1;
