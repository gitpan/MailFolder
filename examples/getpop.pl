#!/usr/bin/perl -I/home/kjj/perldevel/Folder/blib/lib

use Net::POP3;
use Mail::Folder::Mbox;

$server = 'mailhost';
$mailbox = 'mailbox';
$user = 'YOUR_POP_ACCOUNT_NAME';
$pass = 'YOUR_POP_ACCOUNT_PASSWORD';

autoflush STDOUT 1;

$folder = Mail::Folder->new('mbox', $mailbox, Create => 1);

($pop = Net::POP3->new($server, Debug => 0)) ||
  die("can't connect to $server\n");

$qtymsgs = $pop->login($user, $pass);

if (defined($qtymsgs)) {
  if ($qtymsgs) {
    print("$qtymsgs messages: ");
    foreach $msgnum (1 .. $qtymsgs) {
      if ($msg = $pop->get($msgnum)) {
	print('.');
	$mref = Mail::Internet->new($msg);
	$folder->append_message($mref);
	push(@deletes, $msgnum);
      } else {
	print('x');
      }
    }
    print("\n");
    $folder->sync if (defined(@deletes));
  } else { print("no messages\n"); }
} else { warn("can't log into $server\n"); }

$folder->close;

map { $pop->delete($_) } @deletes;
$pop->quit;
