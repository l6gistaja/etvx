#!/usr/bin/perl

use Data::Dumper;
use Schedule::Cron;
use DBI;
# you also need DBD:SQLite;


my $dbh = DBI->connect("dbi:SQLite:development.sqlite3", "", "",
{RaiseError => 1, AutoCommit => 1});

my $sth = $dbh->prepare('SELECT fvalue FROM configuration WHERE category=\'perlCfg\' AND name=\'downloadCommandFormat\'');
$sth->execute();
my $result = $sth->fetchrow_hashref();
my $downloader = $result->{'fvalue'};
$sth->finish;

my @cronjobs = qw();
my @dlids = qw();
my $sql = 'SELECT t0ts, id, name, strftime(\' %M %H %d %m %w\',t0ts,\'unixepoch\') AS cron FROM broadcasts WHERE download_started = 0 AND t0ts > strftime(\'%s\',datetime(\'now\',\'localtime\'))';
#print $sql."\n";
$sth = $dbh->prepare($sql);
$sth->execute();
my $lateststart = 0;
my $result;
while($result = $sth->fetchrow_hashref()) {
    push @cronjobs, cronifystr($result->{'cron'});
    push @cronjobs, $result->{'id'};
    push @dlids, $result->{'id'};
    if(0+$result->{'t0ts'} > $lateststart) { $lateststart = 0+$result->{'t0ts'}; }
}
$sth->finish;

if($#dlids < 0) { exit; }

$sth = $dbh->prepare(
    'INSERT INTO crondaemons (pid,broadcastids,downloads,lastdownloadstart,created_at,exittime) VALUES (?,?,?,?,datetime(\'now\',\'localtime\'),0);'
);
$sth->execute($$, join(",",@dlids), ($#dlids+1), $lateststart);
$sth->finish;

# Subroutines to be called
sub dispatcher { 
    print "ID:   ",shift,"\n"; 
    print "Args: ","@_","\n";
}

sub create_command {
    $sth2 = $dbh->prepare('SELECT b.t1ts-b.t0ts AS dt, c.flv_filetemplate, strftime(\'%Y%m%d-%H%M\',b.t0ts,\'unixepoch\') AS times, c.stream_url, c.flv_directory FROM broadcasts b, channels c WHERE b.id=? AND b.channel_id = c.id');
    $sth2->execute($_[0]);
    %y = ('cmd' => '', 'file' => '');
    if($result2 = $sth2->fetchrow_hashref()) {
        $y{'file'} = sprintf($result2->{'flv_filetemplate'}, $result2->{'times'});
        $y{'cmd'} = sprintf($downloader,
            $result2->{'dt'}, $result2->{'stream_url'},
                $result2->{'flv_directory'}.$y{'file'}
        );
    }
    $sth2->finish;
    return %y;
}

sub download { 
    
    %cdata = create_command($_[0]);
    
    if ($pid = fork) {
    
        $sth2 = $dbh->prepare('UPDATE broadcasts SET updated_at=strftime(\'%s\',datetime(\'now\',\'localtime\')), download_started=1, filename=?, ppid=?, pid=? WHERE id=?;');
        $sth2->execute($cdata{'file'}, $$, $pid, $_[0]);
        $sth2->finish;
    
    } else {
            exec($cdata{'cmd'});
    }
    
    #system(create_command($_[0]));
}

sub cronifystr {
    $crnstr = $_[0];
    $crnstr =~s/\s0/ /g;
    $crnstr =~s/^\s//;
    # Sunday - missing 0 in end
    $crnstr =~s/\s$/ 0/;
    return $crnstr;
}

sub suicide {
    $sth2 = $dbh->prepare('UPDATE crondaemons SET exittime = strftime(\'%s\',datetime(\'now\',\'localtime\')) WHERE pid=?');
    $sth2->execute($_[0]);
    $sth2->finish;
    exec('kill '.$_[0]);
}

#exit;

# Create new object with default dispatcher
my $cron = new Schedule::Cron(\&dispatcher);

for($i=0; $i<$#cronjobs; $i+=2) {
    # Add dynamically  crontab entries
    $cron->add_entry($cronjobs[$i],\&download,$cronjobs[$i+1]);
}

# finally: suicide minute after start of last download
$sth = $dbh->prepare('SELECT strftime(\' %M %H %d %m %w\','.$lateststart.'+60,\'unixepoch\') AS exittime');
$sth->execute();
if($result = $sth->fetchrow_hashref()) {
    $cron->add_entry(cronifystr($result->{'exittime'}),\&suicide,$$);
}

#print Dumper($cron->list_entries());

# Run scheduler 
print $cron->run();

$sth->finish;
$dbh->disconnect;