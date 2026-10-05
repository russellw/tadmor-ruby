require "zlib"

# A minimal PDF writer, enough for printable business documents.
#
# Pages use the PDF "standard 14" Helvetica fonts, which every conforming
# reader has built in, so no font program is embedded; only their advance
# widths (PdfMetrics) are needed to measure text. Coordinates are in points
# with the origin at the bottom left. Text is WinAnsi (Windows-1252), and
# characters outside it render as '?'.
module Pdf
  REGULAR = "/F1".freeze
  BOLD = "/F2".freeze
  WIDTHS = { REGULAR => PdfMetrics::HELVETICA, BOLD => PdfMetrics::HELVETICA_BOLD }.freeze
  A4 = [595.28, 841.89].freeze

  module_function

  def winansi(s) = s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").b

  def width(font, size, s) = winansi(s).bytes.sum { WIDTHS[font][_1] } * size / 1000.0

  # A coordinate without trailing zeros.
  def num(v)
    s = format("%.4f", v).sub(/0+\z/, "").sub(/\.\z/, "")
    ["", "-0"].include?(s) ? "0" : s
  end

  def string(s)
    escaped = winansi(s).gsub(/[\\()]/n) { "\\#{_1}" }.gsub("\n".b, "\\n".b).gsub("\r".b, "\\r".b)
    "(".b + escaped + ")".b
  end

  class Page
    attr_reader :width, :height, :content

    def initialize(width, height)
      @width, @height = width, height
      @content = +"".b
    end

    def text(font, size, x, y, s, gray = 0)
      @content << "BT #{font} #{Pdf.num(size)} Tf #{Pdf.num(gray)} g #{Pdf.num(x)} #{Pdf.num(y)} Td ".b
      @content << Pdf.string(s) << " Tj ET\n".b
    end

    def line(x1, y1, x2, y2, w, gray)
      @content << "#{Pdf.num(w)} w #{Pdf.num(gray)} G #{Pdf.num(x1)} #{Pdf.num(y1)} m #{Pdf.num(x2)} #{Pdf.num(y2)} l S\n".b
    end
  end

  class Document
    attr_reader :pages

    def initialize
      @pages = []
    end

    def add_page(width = A4[0], height = A4[1])
      Page.new(width, height).tap { @pages << _1 }
    end

    # Serialize: 1 catalog, 2 page tree, 3/4 fonts, then a page and a
    # compressed content stream per page.
    def bytes
      buf = +"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
      offsets = []
      obj = lambda do |body|
        offsets << buf.bytesize
        buf << "#{offsets.size} 0 obj\n".b << body.b << "\nendobj\n".b
      end

      kids = @pages.each_index.map { "#{5 + 2 * _1} 0 R" }.join(" ")
      obj.call("<< /Type /Catalog /Pages 2 0 R >>")
      obj.call("<< /Type /Pages /Kids [#{kids}] /Count #{@pages.size} >>")
      obj.call("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
      obj.call("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
      @pages.each_with_index do |p, i|
        obj.call("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{Pdf.num(p.width)} #{Pdf.num(p.height)}] " \
                 "/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents #{6 + 2 * i} 0 R >>")
        data = Zlib::Deflate.deflate(p.content)
        obj.call("<< /Length #{data.bytesize} /Filter /FlateDecode >>\nstream\n".b + data + "\nendstream".b)
      end
      xref = buf.bytesize
      buf << "xref\n0 #{offsets.size + 1}\n0000000000 65535 f \n".b
      offsets.each { buf << format("%010d 00000 n \n", _1).b }
      buf << "trailer\n<< /Size #{offsets.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
    end
  end
end
