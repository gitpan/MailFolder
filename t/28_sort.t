#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Mbox;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink('testfolders/mbox_1');
system("cp testfolders/mbox_seed testfolders/mbox_1");

$sort_spec = sub {
  my($message1) = shift;
  my($message2) = shift;

  return($message2->get('subject') cmp $message1->get('subject'));
};

print "1..4\n";

okay_if(1, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
@msgs = $folder->sort($sort_spec);
okay_if(2, ($msgs[0] == 2));
okay_if(3, ($msgs[1] == 1));
okay_if(4, $folder->close);

1;
