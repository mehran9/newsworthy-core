# Used before for Alchemy API

namespace :import do
  task :categories => :environment do
    require 'csv'
    file = File.join(Rails.root, 'config', 'AlchemyAPI_TaxonomyCategoriesToUse.csv')
    CSV.foreach(file, {headers: true}) do |row|
      root = Category.find_or_create_by(name: row['LEVEL 1'])

      parent = root
      (2..5).each {|i|
        if !!row["LEVEL #{i}"]
          parent = parent.children.find_or_create_by(name: row["LEVEL #{i}"])
        else
          break
        end
      }
    end
  end
end
