# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

package App::MtAws::RetrievalFetchJob;

use strict;
use warnings;
use utf8;
use base qw/App::MtAws::Job/;
use App::MtAws::FileUploadJob;
use App::MtAws::RetrievalDownloadJob;

use JSON::XS;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{archives}||die;
    $self->{raised} = 0;
    $self->{downloads} ||= [];
    $self->{seen} ||= {};
    return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self) = @_;
	if ($self->{raised}) {
		return ("wait");
	} else {
		$self->{raised} = 1;
		return ("ok", App::MtAws::Task->new(id => "retrieval_fetch_job",action=>"retrieval_fetch_job", data => { marker => $self->{marker} } ));
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	if ($self->{raised}) {
		my $json = JSON::XS->new->allow_nonref;
		my $scalar = $json->decode( $task->{result}->{response} );
		for my $job (@{$scalar->{JobList}}) {
			#print "$job->{Completed}|$job->{JobId}|$job->{ArchiveId}\n";
			if ($job->{Action} eq 'ArchiveRetrieval' && $job->{Completed} && $job->{StatusCode} eq 'Succeeded') {
				if (my $a = $self->{archives}->{$job->{ArchiveId}}) {
					if (!$self->{seen}->{ $job->{ArchiveId} }) {
						$self->{seen}->{ $job->{ArchiveId} }=1;
						$a->{jobid} = $job->{JobId};
						push @{$self->{downloads}}, $a;
					}
				}
			}
		}
		
		if ($scalar->{Marker}) {
			return ("ok replace", App::MtAws::RetrievalFetchJob->new(archives => $self->{archives}, downloads => $self->{downloads}, seen => $self->{seen}, marker => $scalar->{Marker} ) ); # TODO: we don't need go pagination if we have all archives to download
		} elsif (scalar @{$self->{downloads}}) {
			return ("ok replace", App::MtAws::RetrievalDownloadJob->new(archives=>$self->{downloads})); #TODO allow parallel downloads while fetching job list
		} else {
			return ("done");
		}
	} else {
		die;
	}
}
	
1;