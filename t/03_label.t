#!/usr/bin/perl       # -*-perl-*-

use Mail::Folder::Emaul;

sub okay_if { print(($_[1] ? "ok $_[0]\n" : "not ok $_[0]\n")) }

for $dir (qw(testfolders testfolders/emaul_seed)) {
  (-e $dir) || die("$dir doesn't exist\n");
  (-d $dir) || die("$dir isn't a directory\n");
  (-r $dir) || die("dir isn't readable\n");
}
system("rm -rf testfolders/emaul_1");
mkdir("testfolders/emaul_1", 0755);
system("cp testfolders/emaul_seed/[0-9] testfolders/emaul_1");
system("cp testfolders/emaul_seed/.msg_labels testfolders/emaul_1");
system("echo 1 >testfolders/emaul_1/.current_msg");

print "1..30\n";

okay_if(1, $folder = new Mail::Folder('emaul', "testfolders/emaul_1"));

@msgs = $folder->message_list;
okay_if(2, ($#msgs == 1));	# correct number of messages?

okay_if(3, $folder->label_exists(1, 'one'));
okay_if(4, $folder->label_exists(3, 'three'));
okay_if(5, $folder->label_exists(1, 'atest'));
okay_if(6, $folder->label_exists(3, 'atest'));
okay_if(7, !$folder->label_exists(1, 'three'));
okay_if(8, !$folder->label_exists(3, 'one'));
okay_if(9, !$folder->label_exists(1, 'arf'));
okay_if(10, $folder->delete_label(1, 'one'));
okay_if(11, $folder->clear_label('atest') == 2);
okay_if(12, $folder->delete_label(3, 'three'));

okay_if(13, $folder->add_label(1, 'arf'));
okay_if(14, $folder->label_exists(1, 'arf'));
okay_if(15, $folder->add_label(1, 'greeble'));
$folder->add_label(1, 'zort');
@labels = $folder->list_labels(1);
okay_if(16, $#labels == 2);
okay_if(17, $folder->delete_label(1, 'arf'));
okay_if(18, !$folder->label_exists(1, 'arf'));
@msgs = $folder->select_label('arf');
okay_if(19, $#msgs == -1);
@msgs = $folder->select_label('zort');
okay_if(20, $#msgs == 0);
okay_if(21, $folder->clear_label('zort'));
okay_if(22, !$folder->label_exists(1, 'zort'));
okay_if(23, $folder->add_label(3, 'blah'));
okay_if(24, $folder->first_labeled_message('blah') == 3);
okay_if(25, !$folder->first_labeled_message('none'));
okay_if(26, $folder->last_labeled_message('greeble') == 1);
okay_if(27, !$folder->last_labeled_message('none'));
okay_if(28, $folder->next_labeled_message(1, 'blah') == 3);
okay_if(29, $folder->prev_labeled_message(3, 'greeble') == 1);

okay_if(30, $folder->close);

1;
