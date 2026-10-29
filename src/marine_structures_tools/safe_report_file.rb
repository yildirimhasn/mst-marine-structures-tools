# frozen_string_literal: true
require 'tempfile'
module MAG
 module MarineStructuresTools
  module SafeReportFile
   extend self
   def write(path,content)
    temporary=Tempfile.new(['mst-export-','.tmp'],File.dirname(path),encoding:'UTF-8')
    begin
     temporary.write(content);temporary.flush;temporary.fsync;temporary.close
     File.rename(temporary.path,path)
    ensure
     temporary.close!
    end
    path
   end
  end
 end
end
