
# module Jekyll
#  class TagIndex < Page
    
#     def initialize(site, base, dir, tag, posts)
#         @site = site
#         @base = base
#         @dir = dir
#         @name = 'index.html'
        
#         self.process(@name)
#         puts "initializeing TagIndex"
#         #self.read_yaml(File.join(base, '_layouts'), 'tag_index.html')
#         tag_index = (site.config['tag_page_layout'] || 'tag-page') + '.html'
#         self.read_yaml(File.join(base, '_layouts'), tag_index)
#         self.data['tag'] = tag
#         tag_title_prefix = site.config['tag_title_prefix'] || 'Posts Tagged &ldquo;'
#         tag_title_suffix = site.config['tag_title_suffix'] || '&rdquo;'
#         self.data['title'] = "#{tag_title_prefix}#{tag}#{tag_title_suffix}"
#     end
#  end
#     #   def initialize(site, base, dir, tag, articles)
#     #     @site = site
#     #     @base = base
#     #     @dir = dir
#     #     @name = 'index.html'
#     #     self.process(@name)
#     #     tag_index = (site.config['tag_page_layout'] || 'tag-page') + '.html'
#     #     self.read_yaml(File.join(base, '_layouts'), tag_index)
#     #     self.data['tag'] = tag
#     #     self.data['articles'] = articles.sort { |p1, p2| p1.date <=> p2.date }
#     #     tag_title_prefix = site.config['tag_title_prefix'] || 'Tag: '
#     #     self.data['title'] = "#{tag_title_prefix}#{tag}"
#     #     @summary = Summary.empty
#     #   end
#     # end
  
#     class TagGenerator < Generator
#       safe true
  
#       def generate(site)
#         if site.layouts.key? 'tag_index'
#           dir = site.config['tag_page_dir'] || 'tags'
#           puts "generating tag pages"
#           tags = site.pages_by_tag
#           tags.keys.sort {|k1, k2| k1 <=> k2}.each do |tag|
#            write_tag_index(site, File.join(dir, tag.dir), tag,
#                             tags[tag].to_a.sort {|t1, t2| t1.name <=> t2.name})
#           end
#         end
#       end
  
#       def write_tag_index(site, dir, tag, posts)
#         index = TagIndex.new(site, site.source, dir, tag, posts)
#         index.render(site.layouts, site.site_payload)
#       end
#     end

#     # class TagGenerator < Generator
#     #     safe true
#     #     def generate(site)
#     #       if site.layouts.key? 'tag_index'
#     #         dir = site.config['tag_dir'] || 'tag'
#     #         site.tags.keys.each do |tag|
#     #           write_tag_index(site, File.join(dir, tag), tag)
#     #         end
#     #       end
#     #     end
#     #     def write_tag_index(site, dir, tag)
#     #       index = TagIndex.new(site, site.source, dir, tag)
#     #       index.render(site.layouts, site.site_payload)
#     #       index.write(site.dest)
#     #       site.pages << index
#     #     end
#     #   end

#   end