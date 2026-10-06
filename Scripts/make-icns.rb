#!/usr/bin/env ruby

entries = {
  "icp4" => "icon_16x16.png",
  "icp5" => "icon_32x32.png",
  "icp6" => "icon_64x64.png",
  "ic07" => "icon_128x128.png",
  "ic08" => "icon_256x256.png",
  "ic09" => "icon_512x512.png",
  "ic10" => "icon_1024x1024.png",
}

abort "Usage: make-icns.rb ICON_DIRECTORY OUTPUT.icns" unless ARGV.length == 2

directory, output = ARGV
elements = entries.map do |type, filename|
  image = File.binread(File.join(directory, filename))
  type + [image.bytesize + 8].pack("N") + image
end.join

File.binwrite(output, "icns" + [elements.bytesize + 8].pack("N") + elements)
