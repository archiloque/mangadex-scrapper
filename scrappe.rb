#!/usr/bin/env ruby

require 'asciidoctor-epub3'
require 'curl'
require 'json'
require 'zip'
require 'uri'

if ARGV.length != 2
  raise "Two mandatory parameters that should be 1) the manga main URL and 2) the language (like 'en')"
end

main_url_string = ARGV[0]
manga_lang = ARGV[1]

main_url_parsed = URI(main_url_string)
unless main_url_parsed.scheme == 'https'
  raise "URL seems wrong, scheme is not https [#{main_url_string}]"
end

splitted_main_url = main_url_parsed.path.split("/")
manga_name = splitted_main_url.last
manga_id = splitted_main_url[-2]
manga_dir = "#{manga_name}-#{manga_lang}"

unless Dir.exist?(manga_dir)
  Dir.mkdir(manga_dir)
end

page_size = 100

# @param [String] url
# @param [Integer] sleep
# @return [String]
def download(url, sleep)
  p "Downloading [#{url}]"
  sleep(sleep)
  response = Curl.get(url)
  unless response.response_code == 200
    raise response.to_s
  end
  response.body
end

def chapter_list_url(manga_id, page_size, page_index)
  "https://api.mangadex.org/manga/#{manga_id}/feed?limit=#{page_size}&includes[]=scanlation_group&includes[]=user&order[volume]=desc&order[chapter]=desc&offset=#{page_index * page_size}&contentRating[]=safe&contentRating[]=suggestive&contentRating[]=erotica&contentRating[]=pornographic"
end

main_page_file = File.join(manga_dir, 'page-0.json')
unless File.exist?(main_page_file)
  File.write(main_page_file, download(chapter_list_url(manga_id, page_size, 0), 5))
end

main_page_content = JSON.parse(IO.read(main_page_file))
total_content = main_page_content['total']
index_total_number = (total_content.to_f / page_size).ceil

0.upto(index_total_number) do |page_index|
  page_file = File.join(manga_dir, "page-#{page_index}.json")
  unless File.exist?(page_file)
    File.write(page_file, download(chapter_list_url(manga_id, page_size, page_index), 5))
  end
end

chapters = []

0.upto(index_total_number) do |page_index|
  page_file = File.join(manga_dir, "page-#{page_index}.json")
  page_content = JSON.parse(IO.read(page_file))
  page_content['data'].each do |entry|
    content_type = entry['type']
    content_lang = entry['attributes']['translatedLanguage']
    if content_lang != manga_lang
      p "Skip content in [#{content_lang}]"
    elsif content_type != 'chapter'
      p "Skip content of type [#{content_type}]"
    else
      chapters << entry
    end
  end
end

# @param [String] image_path
# @param [String] image_index
# @param [String] images_number_size
# @return [String]
def image_file(image_path, image_index, images_number_size)
  image_extension = File.extname(image_path)
  "#{image_index.to_s.rjust(images_number_size, "0")}#{image_extension}"
end

# @param [Hash] chapter
# @param [String] manga_dir
# @param [String] manga_lang
# @param [String] manga_name
# @return [void]
def process_chapter(chapter, manga_dir, manga_lang, manga_name)
  chapter_number = chapter['attributes']['chapter']
  p "Processing chapter [#{chapter_number}]"
  if chapter['attributes']['externalUrl']
    p "Chapter has an external URL, skiping it"
    return
  end

  chapter_file = File.join(manga_dir, "chapter-#{chapter_number}.json")
  unless File.exist?(chapter_file)
    chapter_id = chapter['id']
    url = "https://api.mangadex.org/at-home/server/#{chapter_id}?forcePort443=false"
    File.write(chapter_file, download(url, 5))
  end

  chapter_dir = File.join(manga_dir, chapter_number)
  unless Dir.exist?(chapter_dir)
    Dir.mkdir(chapter_dir)
  end
  chapter_content = JSON.parse(IO.read(chapter_file))
  images_number_size = chapter_content['chapter']['data'].length.to_s.length
  chapter_hash = chapter_content['chapter']['hash']

  chapter_content['chapter']['data'].each_with_index do |image_path, image_index|
    image_file = File.join(chapter_dir, image_file(image_path, image_index, images_number_size))
    unless File.exist?(image_file)
      url = "https://uploads.mangadex.org/data/#{chapter_hash}/#{image_path}"
      File.write(image_file, download(url, 2))
    end
  end

  chapter_cbz = File.join(manga_dir, "#{manga_dir}-#{chapter_number}.cbz")
  unless File.exist?(chapter_cbz)
    Zip::File.open(chapter_cbz, create: true) do |zipfile|
      chapter_content['chapter']['data'].each_with_index do |image_path, image_index|
        image_file_name = image_file(image_path, image_index, images_number_size)
        image_full_path = File.join(chapter_dir, image_file_name)
        zipfile.add(image_file_name, image_full_path)
      end
    end
  end

  chapter_adoc_file = File.join(manga_dir, "#{manga_dir}-#{chapter_number}.adoc")
  unless File.exist?(chapter_adoc_file)
    File.open(chapter_adoc_file, 'w') do |file|
      file << "= #{manga_name} - #{manga_lang} - Chapter #{chapter_number}\n"
      file << ":lang: #{manga_lang}\n"
      chapter_content['chapter']['data'].each_with_index do |image_path, image_index|
        image_file_name = image_file(image_path, image_index, images_number_size)
        image_full_path = File.join(chapter_number, image_file_name)
        if image_index == 0
          file << ":front-cover-image: #{image_full_path}\n"
          file << "\n"
        end
        file << "image::#{image_full_path}[]\n"
      end
    end
  end

  chapter_epub_file = File.join(manga_dir, "#{manga_dir}-#{chapter_number}.epub")
  unless File.exist?(chapter_epub_file)
    Asciidoctor.convert_file(chapter_adoc_file, doctype: :book, safe: :unsafe, backend: 'epub3')
  end
end

chapters.reverse.each do |chapter|
  process_chapter(chapter, manga_dir, manga_lang, manga_name)
end

p "DONE !"
