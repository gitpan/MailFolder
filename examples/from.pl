#!/usr/bin/perl -Iblib/lib

use Mail::Folder::Mbox;
use Mail::Address;

$maildir  = '/var/spool/mail';

$user = `whoami`;
chomp($user);
$mailfile = "$maildir/$user";

die("No mail\n") if (!-f $mailfile);

$folder = new Mail::Folder('mbox', $mailfile);

foreach $msg ($folder->message_list) {
  $mref = $folder->get_header($msg);
  $mref->fold_length(1024);
  $from = $mref->get('From'); chomp($from);
  $subj = $mref->get('Subject'); chomp($subj);
  @addrs = Mail::Address->parse($from);

  if ($addrs[0]->phrase) {
    $from = $addrs[0]->phrase;
    $from =~ s/^"//; $from =~ s/"$//;
  } elsif ($addrs[0]->comment) {
    $from = $addrs[0]->comment;
    $from =~ s/^\(//; $from =~ s/\)$//;
  } else {
    $from = $addrs[0]->address;
  }

  printf("%-20s  %s\n", $from, $subj);
}

$folder->close;
