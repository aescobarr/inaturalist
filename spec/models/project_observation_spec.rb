require File.dirname(__FILE__) + '/../spec_helper.rb'

describe ProjectObservation, "creation" do
  it "should queue a DJ job for the list" do
    stamp = Time.now
    ProjectObservation.make(:observation => Observation.make(:taxon => Taxon.make))
    jobs = Delayed::Job.all(:conditions => ["created_at >= ?", stamp])
    # jobs.each {|j| puts j.handler}
    jobs.select{|j| j.handler =~ /\:refresh_project_list\n/}.should_not be_blank
  end
end

describe ProjectObservation, "destruction" do
  it "should queue a DJ job for the list" do
    stamp = Time.now
    project_observation = ProjectObservation.make(:observation => Observation.make(:taxon => Taxon.make))
    jobs = Delayed::Job.destroy_all
    project_observation.destroy
    Delayed::Job.last.should_not be_blank
    Delayed::Job.last.handler.should match(/\:refresh_project_list\n/)
  end
end

describe ProjectObservation, "observed_by_project_member?" do
  
  before(:each) do 
    @project_user = ProjectUser.make
    @project = @project_user.project
    @observation = Observation.make(:user => @project_user.user)
    @po1 = ProjectObservation.make(:project => @project, :observation => @observation)
    @po2 = ProjectObservation.make(:observation => @observation)
  end
  
  it "should be true if observed by a member of the project" do
    @po1.should be_observed_by_project_member
  end
  
  it "should be false unless observed by a member of the project" do
    @po2.should_not be_observed_by_project_member
  end
  
end

describe ProjectObservation, "observed_in_place_bounding_box?" do
  
  it "should work" do
    place = Place.make(:latitude => 0, :longitude => 0, :swlat => -1, :swlng => -1, :nelat => 1, :nelng => 1)
    observation = Observation.make(:latitude => 0.5, :longitude => 0.5)
    project_observation = ProjectObservation.make(:observation => observation)
    project_observation.should be_observed_in_bounding_box_of(place)
  end
  
end

describe ProjectObservation, "georeferenced?" do
  
  it "should work" do
    observation = Observation.make(:latitude => 0.5, :longitude => 0.5)
    project_observation = ProjectObservation.make(:observation => observation)
    project_observation.should be_georeferenced
  end
  
end

describe ProjectObservation, "identified?" do
  
  it "should work" do
    project_observation = ProjectObservation.make
    observation = project_observation.observation
    project_observation.should_not be_identified
    observation.update_attributes(:taxon => Taxon.make)
    project_observation.should be_identified
  end
  
end
