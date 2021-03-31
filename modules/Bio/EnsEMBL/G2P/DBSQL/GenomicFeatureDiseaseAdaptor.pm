=head1 LICENSE
 
See the NOTICE file distributed with this work for additional information
regarding copyright ownership.
 
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
 
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 
=cut
use strict;
use warnings;

package Bio::EnsEMBL::G2P::DBSQL::GenomicFeatureDiseaseAdaptor;

use Bio::EnsEMBL::G2P::GenomicFeatureDisease;
use Bio::EnsEMBL::G2P::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::G2P::GFDDiseaseSynonym;
use DBI qw(:sql_types);

our @ISA = ('Bio::EnsEMBL::G2P::DBSQL::BaseAdaptor');

sub store {
  my $self = shift;
  my $gfd = shift;
  my $user = shift;
  my $dbh = $self->dbc->db_handle;

  if (!ref($gfd) || !$gfd->isa('Bio::EnsEMBL::G2P::GenomicFeatureDisease')) {
    die('Bio::EnsEMBL::G2P::GenomicFeatureDisease arg expected');
  }

  if (!ref($user) || !$user->isa('Bio::EnsEMBL::G2P::User')) {
    die('Bio::EnsEMBL::G2P::User arg expected');
  }

  if (! (defined $gfd->{allelic_requirement} || defined $gfd->{allelic_requirement_attrib})) {
    die "allelic_requirement or allelic_requirement_attrib is required\n";
  }

  if (! (defined $gfd->{mutation_consequence} || defined $gfd->{mutation_consequence_attrib})) {
    die "mutation_consequence or mutation_consequence_attrib is required\n";
  }
  
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;

  foreach my $key (qw/allelic_requirement mutation_consequence/)  {

    if (defined $gfd->{$key} && ! defined $gfd->{"$key\_attrib"}) {
      my $attrib = $attribute_adaptor->get_attrib($key, $gfd->{$key});
      if (!$attrib) {
        die "Could not get $key attrib id for value ", $gfd->{$key}, "\n";
      }
      $gfd->{"$key\_attrib"} = $attrib;
    }

    if (defined $gfd->{"$key\_attrib"} && ! defined $gfd->{$key}) {
      my $value = $attribute_adaptor->get_value($key, $gfd->{"$key\_attrib"});
      if (!$value) {
        die "Could not get $key value for attrib id ", $gfd->{"$key\_attrib"}, "\n";
      }
      $gfd->{$key} = $value;
    }
  }

  my $sth = $dbh->prepare(q{
    INSERT INTO genomic_feature_disease(
      genomic_feature_id,
      disease_id,
      allelic_requirement,
      allelic_requirement_attrib,
      mutation_consequence,
      mutation_consequence_attrib,
      restricted_mutation_set
    ) VALUES (?, ?, ?, ?, ?)
  });

  $sth->execute(
    $gfd->{genomic_feature_id},
    $gfd->{disease_id},
    $gfd->{allelic_requirement},
    $gfd->{allelic_requirement_attrib},
    $gfd->{mutation_consequence},
    $gfd->{mutation_consequence_attrib},
    $gfd->restricted_mutation_set || 0
  );

  $sth->finish();
  
  # get dbID
  my $dbID = $dbh->last_insert_id(undef, undef, 'genomic_feature_disease', 'genomic_feature_disease_id'); 
  $gfd->{genomic_feature_disease_id} = $dbID;

  $self->update_log($gfd, $user, 'create');

  return $gfd;
}

sub update {
  my $self = shift;
  my $gfd = shift;
  my $user = shift;
  my $dbh = $self->dbc->db_handle;

  if (!ref($gfd) || !$gfd->isa('Bio::EnsEMBL::G2P::GenomicFeatureDisease')) {
    die('Bio::EnsEMBL::G2P::GenomicFeatureDisease arg expected');
  }

  if (!ref($user) || !$user->isa('Bio::EnsEMBL::G2P::User')) {
    die('Bio::EnsEMBL::G2P::User arg expected');
  }

  my $sth = $dbh->prepare(q{
    UPDATE genomic_feature_disease
    SET
      genomic_feature_id = ?,
      disease_id = ?,
      restricted_mutation_set = ?
    WHERE genomic_feature_disease_id = ? 
  });

  $sth->execute(
    $gfd->genomic_feature_id,
    $gfd->disease_id,
    $gfd->restricted_mutation_set,
    $gfd->dbID
  );
  $sth->finish();

  $self->update_log($gfd, $user, 'update');

  return $gfd;
}

sub update_log {
  my $self = shift;
  my $gfd = shift;
  my $user = shift;
  my $action = shift;

  my $GFD_log_adaptor = $self->db->get_GenomicFeatureDiseaseLogAdaptor;
  my $gfdl = Bio::EnsEMBL::G2P::GenomicFeatureDiseaseLog->new(
    -genomic_feature_disease_id => $gfd->dbID,
    -disease_id => $gfd->disease_id,
    -genomic_feature_id => $gfd->genomic_feature_id,
    -user_id => $user->dbID,
    -action => $action, 
    -adaptor => $GFD_log_adaptor,
  );
  $GFD_log_adaptor->store($gfdl);
}

sub fetch_by_dbID {
  my $self = shift;
  my $genomic_feature_disease_id = shift;
  return $self->SUPER::fetch_by_dbID($genomic_feature_disease_id);
}

sub fetch_all_by_Disease {
  my $self = shift;
  my $disease = shift;
  my $disease_id = $disease->dbID;
  my $constraint = "gfd.disease_id=$disease_id";
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_GenomicFeature {
  my $self = shift;
  my $genomic_feature = shift;
  my $genomic_feature_id = $genomic_feature->dbID;
  my $constraint = "gfd.genomic_feature_id=$genomic_feature_id";
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_GenomicFeature_constraints {
  my $self = shift;
  my $genomic_feature = shift;
  my $constraints_hash = shift;
  my @constraints = ();
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;

  while ( my ($key, $value) = each (%$constraints_hash)) {
    if ($key eq 'allelic_requirement') {
      my $allelic_requriement_attrib = $attribute_adaptor->get_attrib('allelic_requirement', $value); 
      push @constraints, "gfd.allelic_requirement_attrib='$allelic_requriement_attrib'";
    } elsif ($key eq 'mutation_consequence') {
      my $mutation_consequence_attrib = $attribute_adaptor->get_attrib('mutation_consequence', $value); 
      push @constraints, "gfd.mutation_consequence_attrib='$mutation_consequence_attrib'";
    } else {
      die "Did not recognise constraint: $key. Supported constraints are: allelic_requirement and mutation_consequence\n";
    }
  }

  my $genomic_feature_id = $genomic_feature->dbID;
  push @constraints, "gfd.genomic_feature_id=$genomic_feature_id";
  return $self->generic_fetch(join(' AND ', @constraints));
}

sub fetch_all_by_GenomicFeature_Disease {
  my $self = shift;
  my $genomic_feature = shift;
  my $disease = shift;
  my $genomic_feature_id = $genomic_feature->dbID;
  my $disease_id = $disease->dbID;
  my $constraint = "(gfd.disease_id=$disease_id OR gfdds.disease_id=$disease_id ) AND gfd.genomic_feature_id=$genomic_feature_id;";
  return $self->generic_fetch($constraint);
} 

sub get_statistics {
  my $self = shift;
  my $panels = shift;
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my $confidence_categories = $attribute_adaptor->get_attribs_by_type_value('confidence_category');
  %$confidence_categories = reverse %$confidence_categories;
  my $panel_attrib_ids = join(',', @$panels);
  my $sth = $self->prepare(qq{
    select a.value, gfd.confidence_category_attrib, count(*)
    from genomic_feature_disease gfd, attrib a
    where a.attrib_id = gfd.panel_attrib
    AND gfd.panel_attrib IN ($panel_attrib_ids)
    group by a.value, gfd.confidence_category_attrib;
  });
  $sth->execute;

  my $hash = {};
  while (my ($panel, $confidence_category_attrib_id, $count) = $sth->fetchrow_array) {
    my $confidence_category_value = $confidence_categories->{$confidence_category_attrib_id};
    $hash->{$panel}->{$confidence_category_value} = $count;
  }
  my @results = ();
  my @header = ('Panel', 'confirmed', 'probable', 'possible', 'both RD and IF', 'child IF'); 
  push @results, \@header;
  foreach my $panel (sort keys %$hash) {
    my @row = ();
    push @row, $panel;
    for (my $i = 1; $i <= $#header; $i++) {
      push @row, ($hash->{$panel}->{$header[$i]} || 0) + 0;
    }
    push @results, \@row;
  }

  return \@results;
}

sub fetch_all {
  my $self = shift;
  return $self->generic_fetch();
}

sub _columns {
  my $self = shift;
  my @cols = (
    'gfd.genomic_feature_disease_id',
    'gfd.genomic_feature_id',
    'gfd.disease_id',
    'gfdds.GFD_disease_synonym_id AS gfd_disease_synonym_id',
    'gfd.allelic_requirement_attrib',
    'gfd.mutation_consequence_attrib',
    'gfd.restricted_mutation_set',
  );
  return @cols;
}

sub _tables {
  my $self = shift;
  my @tables = (
    ['genomic_feature_disease', 'gfd'],
    ['GFD_disease_synonym', 'gfdds'],
  );
  return @tables;
}

sub _left_join {
  my $self = shift;

  my @left_join = (
    ['GFD_disease_synonym', 'gfd.genomic_feature_disease_id = gfdds.genomic_feature_disease_id'],
  );

return @left_join;
}

sub _objs_from_sth {
  my ($self, $sth) = @_;
  my %row;
  $sth->bind_columns( \( @row{ @{$sth->{NAME_lc} } } ));
  while ($sth->fetch) {
    # we don't actually store the returned object because
    # the _obj_from_row method stores them in a temporary
    # hash _temp_objs in $self
    $self->_obj_from_row(\%row);
  }
  # Get the created objects from the temporary hash
  my @objs = values %{ $self->{_temp_objs} };
  delete $self->{_temp_objs};
  return \@objs;
}

sub _obj_from_row {
  my ($self, $row) = @_;

  my $attribute_adaptor = $self->db->get_AttributeAdaptor;

  my $obj = $self->{_temp_objs}{$row->{genomic_feature_disease_id}};

  unless (defined($obj)) {
    my $allelic_requirement;
    my $mutation_consequence;

    if (defined $row->{allelic_requirement_attrib}) {
      $allelic_requirement = $attribute_adaptor->get_value('allelic_requirement', $row->{allelic_requirement_attrib});
    }

    if (defined $row->{mutation_consequence_attrib}) {
      $mutation_consequence = $attribute_adaptor->get_value('mutation_consequence', $row->{mutation_consequence_attrib});
    }

    my $obj = Bio::EnsEMBL::G2P::GenomicFeatureDisease->new(
      -genomic_feature_disease_id => $row->{genomic_feature_disease_id},
      -genomic_feature_id => $row->{genomic_feature_id},
      -disease_id => $row->{disease_id},
      -allelic_requirement_attrib => $row->{allelic_requirement_attrib},
      -allelic_requirement => $allelic_requirement,
      -mutation_consequence_attrib => $row->{mutation_consequence_attrib},
      -mutation_consequnece => $mutation_consequence,
      -restricted_mutation_set => $row->{restricted_mutation_set},
      -adaptor => $self,
    );
    $self->{_temp_objs}{$row->{genomic_feature_disease_id}} = $obj;
    if (defined $row->{gfd_disease_synonym_id}) {
      $obj->add_gfd_disease_synonym_id($row->{gfd_disease_synonym_id});
    }
  } else {
    if (defined $row->{gfd_disease_synonym_id}) {
      $obj->add_gfd_disease_synonym_id($row->{gfd_disease_synonym_id});
    }
  }
}

1;
