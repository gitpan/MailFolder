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
system("cp testfolders/emaul_seed/.msg_labels testfolders/emaul_1");
system("echo 1 >testfolders/emaul_1/.current_msg");

print "1..22\n";

okay_if(1, $folder = new Mail::Folder('emaul', "testfolders/emaul_1"));

system("cp testfolders/emaul_1/1 testfolders/emaul_1/4");
okay_if(2, ($folder->sync == 1));
@msgs = $folder->message_list;
okay_if(3, ($#msgs == 2));

okay_if(4, $folder->add_label(4, 'atest'));
okay_if(5, ($folder->sync == 0));

okay_if(6, $folder->close);

okay_if(7, $folder->open("testfolders/emaul_1"));
@msgs = $folder->message_list;
okay_if(8, $#msgs == 2);
okay_if(9, $folder->label_exists(1, 'atest'));
okay_if(10, $folder->label_exists(3, 'atest'));
okay_if(11, $folder->label_exists(4, 'atest'));
okay_if(12, $folder->label_exists(1, 'one'));
okay_if(13, $folder->label_exists(3, 'three'));

okay_if(14, $folder->close);

chmod(0555, "testfolders/emaul_1");
okay_if(15, $folder->open("testfolders/emaul_1"));
okay_if(16, $folder->is_readonly);
okay_if(17, $folder->delete_message(3));
okay_if(18, $folder->sync == 0);
okay_if(19, $folder->close);
okay_if(20, $folder->open("testfolders/emaul_1"));
okay_if(21, $folder->message_exists(3));
okay_if(22, $folder->close);

1;

