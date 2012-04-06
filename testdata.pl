#!/usr/bin/perl
use DBI;
# you also need DBD:SQLite;

print "\nRun this script only if you DO understand what it does.\n";
#exit;
print "Broadcasts and history of downloads will be deleted and replaced with test data.\n";

$dbh = DBI->connect("dbi:SQLite:development.sqlite3", "", "",
{RaiseError => 1, AutoCommit => 1});

$sth = $dbh->prepare('DELETE FROM crondaemons;');
$sth->execute();
$sth = $dbh->prepare('DELETE FROM broadcasts;');
$sth->execute();

$minutesbeforestart = 1;
$sth = $dbh->prepare('INSERT INTO broadcasts (t0ts,t1ts,channel_id,name,created_at,download_started) VALUES (strftime(\'%s\',datetime(\'now\',\'localtime\'))+?,strftime(\'%s\',datetime(\'now\',\'localtime\'))+?,?,?,strftime(\'%s\',datetime(\'now\',\'localtime\')),0);');
for($i=0; $i<2; $i++) {
    $sth->execute(
        ($minutesbeforestart+$i)*60,
        5+($minutesbeforestart+$i)*60,
        1+($i%2),
        'testdata.pl: test #'.$i
    );
}

$sth->finish;
$dbh->disconnect;