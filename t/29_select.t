#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Mbox;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

unlink('testfolders/mbox_1');
system("cp testfolders/mbox_seed testfolders/mbox_1");

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

okay_if(1, $folder = new Mail::Folder('mbox', "testfolders/mbox_1"));
@msgs = $folder->select($select_nofind);
okay_if(2, ($#msgs == -1));
@msgs = $folder->select($select_all);
okay_if(3, ($#msgs == 1));
okay_if(4, ($msgs[0] == 1));
okay_if(5, ($msgs[1] == 2));
@msgs = $folder->select($select_greeble);
okay_if(6, ($#msgs == 0));
okay_if(7, ($msgs[0] == 2));
okay_if(8, $folder->close);

1;
