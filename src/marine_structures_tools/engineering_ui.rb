# frozen_string_literal: true
module MAG
  module MarineStructuresTools
    module EngineeringUI
      # Inline reports have no file base. Embed the same local presentation assets.
      def self.decorate(html)
        css = File.read(File.join(__dir__, 'engineering_ui.css'), encoding: 'UTF-8')
        js = File.read(File.join(__dir__, 'engineering_ui.js'), encoding: 'UTF-8')
        assets = "<style>#{css}</style><script>#{js}</script>"
        html.sub('</head>', "#{assets}</head>")
      end
    end
  end
end
