require 'xcodeproj'

project_path = 'Tabs.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target (usually the first one)
target = project.targets.first

# Add the file to the project
file_path = 'Tabs/Models/hsn_codes.json'
group = project.main_group.find_subpath(File.dirname(file_path), true)
group.set_source_tree('SOURCE_ROOT')
file_ref = group.new_reference(File.basename(file_path))

# Add the file to the target's resources build phase
resources_build_phase = target.resources_build_phase
resources_build_phase.add_file_reference(file_ref)

project.save
puts "Added #{file_path} to Xcode project!"
