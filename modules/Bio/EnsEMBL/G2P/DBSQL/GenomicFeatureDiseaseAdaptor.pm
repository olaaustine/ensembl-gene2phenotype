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

  my $aa = $self->db->get_AttributeAdaptor;

  my $sth = $dbh->prepare(q{
    INSERT INTO genomic_feature_disease(
      genomic_feature_id,
      disease_id,
      allelic_requirement_attrib,
      mutation_consequence_attrib,
      restricted_mutation_set
    ) VALUES (?, ?, ?, ?, ?)
  });

  $sth->execute(
    $gfd->{genomic_feature_id},
    $gfd->{disease_id},
    $gfd->{allelic_requirement_attrib},
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

sub _merge_all_duplicated_LGM_by_panel_gene {
  my $self = shift;
  my $user = shift;
  my $gf_id = shift;
  my $disease_id = shift;
  my $panel = shift;
  my $gfd_ids = shift;
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);
  my $base_gfd = $self->_fetch_by_genomic_feature_id_disease_id_panel_id($gf_id, $disease_id, $panel_id);
  my $base_gfd_id = $base_gfd->dbID;
  my @base_gfd_phenotype_ids = map {$_->get_Phenotype->phenotype_id} @{$base_gfd->get_all_GFDPhenotypes};
  my @base_gfd_publication_ids = map {$_->get_Publication->publication_id} @{$base_gfd->get_all_GFDPublications};
  my @base_gfd_organ_ids = map {$_->get_Organ->organ_id} @{$base_gfd->get_all_GFDOrgans};
  my @base_gfd_actions = map {$_->allelic_requirement . '_' . $_->mutation_consequence} @{$base_gfd->get_all_GenomicFeatureDiseaseActions};
  my @base_gfd_disease_synonym_ids = map {$_->disease_id} @{$base_gfd->get_all_GFDDiseaseSynonyms};

  my $dbh = $self->dbc->db_handle;

  foreach my $gfd_id (@$gfd_ids) {
    next if ($gfd_id == $base_gfd_id);
    my $gfd = $self->fetch_by_dbID($gfd_id);
    # Move over all GFD comments
    foreach my $gfd_comment (@{$gfd->get_all_GFDComments}) {
      my $gfd_comment_id = $gfd_comment->dbID;
#      print STDERR "Update genomic_feature_disease_comment set genomic_feature_disease_id=$base_gfd_id where genomic_feature_disease_id=$gfd_id and genomic_feature_disease_comment_id=$gfd_comment_id\n";
      $dbh->do(qq/
        UPDATE genomic_feature_disease_comment
        SET genomic_feature_disease_id=$base_gfd_id
        WHERE genomic_feature_disease_comment_id=$gfd_comment_id/) or die $dbh->errstr;
    }
    foreach my $gfd_phenotype (@{$gfd->get_all_GFDPhenotypes}) {
      my $gfd_phenotype_id = $gfd_phenotype->dbID;
      my $phenotype_id = $gfd_phenotype->get_Phenotype->phenotype_id;
      # If phenotype is already in target GFD
      if (grep {$phenotype_id == $_} @base_gfd_phenotype_ids) {
        foreach my $gfd_phenotype_comment (@{$gfd_phenotype->get_all_GFDPhenotypeComments}) {
          my ($base_gfd_phenotype_id) = map {$_->dbID} grep {$_->get_Phenotype->phenotype_id == $phenotype_id } @{$base_gfd->get_all_GFDPhenotypes};
          my $gfd_phenotype_comment_id = $gfd_phenotype_comment->dbID;
          # move over gfd phenotype comments
#          print STDERR "UPDATE GFD_phenotype_comment SET genomic_feature_disease_phenotype_id = $base_gfd_phenotype_id WHERE GFD_phenotype_comment_id = $gfd_phenotype_comment_id;\n";
          $dbh->do(qq/
            UPDATE GFD_phenotype_comment
            SET genomic_feature_disease_phenotype_id = $base_gfd_phenotype_id
            WHERE GFD_phenotype_comment_id = $gfd_phenotype_comment_id;/) or die $dbh->errstr;
        }
#        print STDERR "DELETE FROM genomic_feature_disease_phenotype WHERE genomic_feature_disease_phenotype_id=$gfd_phenotype_id;\n";
        $dbh->do(qq/DELETE FROM genomic_feature_disease_phenotype WHERE genomic_feature_disease_phenotype_id=$gfd_phenotype_id;/) or die $dbh->errstr;
      } else {
#        print STDERR "UPDATE genomic_feature_disease_phenotype SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_phenotype_id=$gfd_phenotype_id;\n";
        $dbh->do(qq/UPDATE genomic_feature_disease_phenotype SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_phenotype_id=$gfd_phenotype_id;/) or die $dbh->errstr;
      }
      # GFD_phenotype_log: 
#      print STDERR "UPDATE GFD_phenotype_log SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_phenotype_id=$gfd_phenotype_id;\n";
      $dbh->do(qq/UPDATE GFD_phenotype_log SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_phenotype_id=$gfd_phenotype_id;/) or die $dbh->errstr;
    }

    foreach my $gfd_publication (@{$gfd->get_all_GFDPublications}) {
      my $gfd_publication_id = $gfd_publication->dbID;
      my $publication_id = $gfd_publication->get_Publication->publication_id;
      # If publication is already in target GFD
      if (grep {$publication_id == $_} @base_gfd_publication_ids) {
        foreach my $gfd_publication_comment (@{$gfd_publication->get_all_GFDPublicationComments}) {
          my ($base_gfd_publication_id) = map {$_->dbID} grep {$_->get_Publication->publication_id == $publication_id} @{$base_gfd->get_all_GFDPublications};
          my $gfd_publication_comment_id = $gfd_publication_comment->dbID;
          # move over gfd publication comments
#          print STDERR "UPDATE GFD_publication_comment SET genomic_feature_disease_publication_id = $base_gfd_publication_id WHERE GFD_publication_comment_id = $gfd_publication_comment_id;\n";
          $dbh->do(qq/
            UPDATE GFD_publication_comment
            SET genomic_feature_disease_publication_id = $base_gfd_publication_id
            WHERE GFD_publication_comment_id = $gfd_publication_comment_id;/) or die $dbh->errstr;
        }
#        print STDERR "DELETE FROM genomic_feature_disease_publication WHERE genomic_feature_disease_publication_id=$gfd_publication_id;\n";
        $dbh->do(qq/DELETE FROM genomic_feature_disease_publication WHERE genomic_feature_disease_publication_id=$gfd_publication_id;/) or die $dbh->errstr;
      } else {
#        print STDERR "UPDATE genomic_feature_disease_publication SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_publication_id=$gfd_publication_id;\n";
        $dbh->do(qq/UPDATE genomic_feature_disease_publication SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_publication_id=$gfd_publication_id;/) or die $dbh->errstr;
      }
    }
    
    foreach my $gfd_organ (@{$gfd->get_all_GFDOrgans}) {
      my $gfd_organ_id = $gfd_organ->dbID;
      my $organ_id = $gfd_organ->get_Organ->organ_id;
      if (grep {$organ_id == $_} @base_gfd_organ_ids) {
#        print STDERR "DELETE FROM genomic_feature_disease_organ WHERE genomic_feature_disease_organ_id=$gfd_organ_id;\n";
        $dbh->do(qq/DELETE FROM genomic_feature_disease_organ WHERE genomic_feature_disease_organ_id=$gfd_organ_id;/) or die $dbh->errstr;
      } else {
#        print STDERR "UPDATE genomic_feature_disease_organ SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_organ_id=$gfd_organ_id;\n";
        $dbh->do(qq/UPDATE genomic_feature_disease_organ SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_organ_id=$gfd_organ_id;/) or die $dbh->errstr;
      }
    }

    foreach my $gfd_action (@{$gfd->get_all_GenomicFeatureDiseaseActions}) {
      my $gfd_action_id = $gfd_action->dbID;
      my $ar_mc = $gfd_action->allelic_requirement . '_' . $gfd_action->mutation_consequence;
      if (grep {$_ eq $ar_mc} @base_gfd_actions) {
#        print STDERR "DELETE FROM genomic_feature_disease_action WHERE genomic_feature_disease_action_id=$gfd_action_id;\n";
        $dbh->do(qq/DELETE FROM genomic_feature_disease_action WHERE genomic_feature_disease_action_id=$gfd_action_id;/) or die $dbh->errstr;
      } else {
#        print STDERR "UPDATE genomic_feature_disease_action SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_action_id=$gfd_action_id;\n";
        $dbh->do(qq/UPDATE genomic_feature_disease_action SET genomic_feature_disease_id=$base_gfd_id WHERE genomic_feature_disease_action_id=$gfd_action_id;/) or die $dbh->errstr;
      }
    }
    # disease name synonyms
    my $disease_id = $gfd->get_Disease->dbID;
    if (!grep {$_ eq $disease_id} @base_gfd_disease_synonym_ids) {
      my $gfd_disease_synonym_adaptor = $self->db->get_GFDDiseaseSynonymAdaptor;
      my $disease_synonym =  Bio::EnsEMBL::G2P::GFDDiseaseSynonym->new(
        -disease_id => $disease_id,
        -genomic_feature_disease_id => $base_gfd_id,
        -adaptor => $gfd_disease_synonym_adaptor,
      );
      $gfd_disease_synonym_adaptor->store($disease_synonym);
    }

#    print STDERR "Delete GFD $gfd\n";
    $self->delete($gfd, $user);

    @base_gfd_phenotype_ids = map {$_->get_Phenotype->phenotype_id} @{$base_gfd->get_all_GFDPhenotypes};
    @base_gfd_publication_ids = map {$_->get_Publication->publication_id} @{$base_gfd->get_all_GFDPublications};
    @base_gfd_organ_ids = map {$_->get_Organ->organ_id} @{$base_gfd->get_all_GFDOrgans};
    @base_gfd_actions = map {$_->allelic_requirement . '_' . $_->mutation_consequence} @{$base_gfd->get_all_GenomicFeatureDiseaseActions};
    @base_gfd_disease_synonym_ids = map {$_->disease_id} @{$base_gfd->get_all_GFDDiseaseSynonyms};

  }
  return $base_gfd;
}


#LGM = locus, genotype, mechanism
sub _get_all_duplicated_LGM_entries_by_panel {
  my $self = shift;
  my $panel = shift;
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);

  my $sth = $self->prepare(qq{
    select gf.gene_symbol, gfd.genomic_feature_id, gfd.allelic_requirement_attrib, gfd.mutation_consequence_attrib, count(*) as count
    from genomic_feature_disease gfd
    left join genomic_feature gf on gfd.genomic_feature_id = gf.genomic_feature_id
    where gfd.panel_attrib = $panel_id
    group by gfd.genomic_feature_id, gfd.allelic_requirement_attrib, gfd.mutation_consequence_attrib
    having count > 1;
  });
  $sth->execute;
  
  my @results = ();
  while (my ($gene_symbol, $genomic_feature_id, $allelic_requirement_attrib, $mutation_consequence_attrib, $count) = $sth->fetchrow_array) {
    my $allelic_requirement = $attribute_adaptor->attrib_value_for_id($allelic_requirement_attrib);
    my $mutation_consequence = $attribute_adaptor->attrib_value_for_id($mutation_consequence_attrib);
    push @results, {
      gene_symbol => $gene_symbol,
      gf_id => $genomic_feature_id,
      panel_id => $panel_id,
      panel => $panel,
      genomic_feature_id => $genomic_feature_id,
      allelic_requirement_attrib => $allelic_requirement_attrib,
      allelic_requirement => $allelic_requirement,
      mutation_consequence_attrib => $mutation_consequence_attrib,
      mutation_consequence => $mutation_consequence,
      count => $count,
    };
  }

  $sth->finish;
  return \@results;
} 

sub fetch_by_dbID {
  my $self = shift;
  my $genomic_feature_disease_id = shift;
  return $self->SUPER::fetch_by_dbID($genomic_feature_disease_id);
}

sub fetch_all_by_GenomicFeature_Disease_panel {
  my $self = shift;
  my $genomic_feature = shift;
  my $disease = shift;
  my $panel = shift;
  my $genomic_feature_id = $genomic_feature->dbID;
  my $disease_id = $disease->dbID;
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);
  my $constraint = "(gfd.disease_id=$disease_id OR gfdds.disease_id=$disease_id ) AND gfd.genomic_feature_id=$genomic_feature_id AND gfd.panel_attrib=$panel_id;";
  my $result = $self->generic_fetch($constraint);
} 

sub _fetch_by_genomic_feature_id_disease_id_panel_id {
  my $self = shift;
  my $genomic_feature_id = shift;
  my $disease_id = shift;
  my $panel_id = shift;
  my $constraint = "gfd.disease_id=$disease_id AND gfd.genomic_feature_id=$genomic_feature_id AND gfd.panel_attrib=$panel_id;";
  my $result = $self->generic_fetch($constraint);
  return $result->[0];
}

sub fetch_by_GenomicFeature_Disease {
  my $self = shift;
  my $genomic_feature = shift;
  my $disease = shift;
  my $genomic_feature_id = $genomic_feature->dbID;
  my $disease_id = $disease->dbID;
  my $constraint = "gfd.disease_id=$disease_id AND gfd.genomic_feature_id=$genomic_feature_id;";
  my $result = $self->generic_fetch($constraint);
  return $result->[0];
}

sub fetch_by_GenomicFeature_Disease_panel_id {
  my $self = shift;
  my $genomic_feature = shift;
  my $disease = shift;
  my $panel_id = shift;
  my $genomic_feature_id = $genomic_feature->dbID;
  my $disease_id = $disease->dbID;
  my $constraint = "gfd.disease_id=$disease_id AND gfd.genomic_feature_id=$genomic_feature_id AND gfd.panel_attrib=$panel_id;";
  my $result = $self->generic_fetch($constraint);
  return $result->[0];
}

sub fetch_by_GenomicFeature_Disease_panel {
  my $self = shift;
  my $genomic_feature = shift;
  my $disease = shift;
  my $panel = shift;
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);
  return $self->fetch_by_GenomicFeature_Disease_panel_id($genomic_feature, $disease, $panel_id);
}

sub fetch_all_by_GenomicFeature {
  my $self = shift;
  my $genomic_feature = shift;
  my $genomic_feature_id = $genomic_feature->dbID;
  my $constraint = "gfd.genomic_feature_id=$genomic_feature_id";
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_GenomicFeature_panel {
  my $self = shift;
  my $genomic_feature = shift;
  my $panel = shift;

  if ($panel eq 'ALL') {
    return $self->fetch_all_by_GenomicFeature($genomic_feature);
  }
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);

  my $genomic_feature_id = $genomic_feature->dbID;
  my $constraint = "gfd.genomic_feature_id=$genomic_feature_id AND gfd.panel_attrib=$panel_id";
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_GenomicFeature_panels {
  my $self = shift;
  my $genomic_feature = shift;
  my $panels = shift;

  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my @panel_ids = ();
  foreach my $panel (@$panels) {
    my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);
    push @panel_ids, $panel_id;
  } 
  my $genomic_feature_id = $genomic_feature->dbID;
  my $constraint = "gfd.genomic_feature_id=$genomic_feature_id AND gfd.panel_attrib IN (" . join(',', @panel_ids) . ")";
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_Disease {
  my $self = shift;
  my $disease = shift;
  my $disease_id = $disease->dbID;
  my $constraint = "gfd.disease_id=$disease_id";
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_Disease_panel {
  my $self = shift;
  my $disease = shift;
  my $panel = shift;
  if ($panel eq 'ALL') {
    return $self->fetch_all_by_Disease($disease);
  } 
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);

  my $disease_id = $disease->dbID;
  my $constraint = "gfd.disease_id=$disease_id AND gfd.panel_attrib=$panel_id";
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_Disease_panels {
  my $self = shift;
  my $disease = shift;
  my $panels = shift;

  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my @panel_ids = ();
  foreach my $panel (@$panels) {
    my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);
    push @panel_ids, $panel_id;
  } 

  my $disease_id = $disease->dbID;
  my $constraint = "gfd.disease_id=$disease_id AND gfd.panel_attrib IN (" . join(',', @panel_ids) . ")";
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_disease_id {
  my $self = shift;
  my $disease_id = shift;
  my $constraint = qq{gfd.disease_id = ?};
  $self->bind_param_generic_fetch($disease_id, SQL_INTEGER);
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_panel {
  my $self = shift;
  my $panel = shift;
  if ($panel eq 'ALL') {
    return $self->fetch_all();
  } 
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);
  my $constraint = "gfd.panel_attrib=$panel_id";
  return $self->generic_fetch($constraint);
}

sub fetch_all_by_panel_restricted {
  my $self = shift;
  my $panel = shift;
  if ($panel eq 'ALL') {
    return $self->fetch_all();
  } 
  my $attribute_adaptor = $self->db->get_AttributeAdaptor;
  my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);
  my $constraint = "gfd.panel_attrib=$panel_id AND gfd.is_visible = 0";
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

sub fetch_all_by_panel_without_publications {
  my $self = shift;
  my $panel = shift;
  my $constraint = '';
  if ($panel ne 'ALL') {
    my $attribute_adaptor = $self->db->get_AttributeAdaptor;
    my $panel_id = $attribute_adaptor->attrib_id_for_value($panel);
    $constraint = "AND gfd.panel_attrib=$panel_id";
  } 
  my $cols = join ",", $self->_columns();
  my $sth = $self->prepare(qq{
    SELECT $cols FROM genomic_feature_disease gfd
    LEFT JOIN genomic_feature_disease_publication gfdp
    ON gfd.genomic_feature_disease_id = gfdp.genomic_feature_disease_id
    WHERE gfdp.genomic_feature_disease_id IS NULL
    $constraint;
  });

  $sth->execute;
  return $self->_objs_from_sth($sth);
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
      my @ids = split(',', $row->{allelic_requirement_attrib});
      my @values = ();
      foreach my $id (@ids) {
        push @values, $attribute_adaptor->attrib_value_for_id($id);
      }
      $allelic_requirement = join(',', @values);
    }

    if (defined $row->{mutation_consequence_attrib}) {
      $mutation_consequence = $attribute_adaptor->attrib_value_for_id($row->{mutation_consequence_attrib});
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
