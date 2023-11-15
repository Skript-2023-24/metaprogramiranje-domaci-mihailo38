require "google_drive"

# Creates a session. This will prompt the credential via command line for the
# first time and save it to config.json file for later usages.
# See this document to learn how to create config.json:
# https://github.com/gimite/google-drive-ruby/blob/master/doc/authorization.md

class Tabela
  include Enumerable
  attr_accessor :header, :rows, :cols

  # inicijalizacija tabele (argumet: google sheets objekat)
  def initialize(sheet)
    table_start = true
    ignore_row = false
    header = []
    rows = []

    # prolazi kroz google sheets po redovima i kolonama
    (1..sheet.num_rows).each do |row|
      cell_row = []
      (1..sheet.num_cols).each do |col|
        cell = sheet[row, col]
        if cell.downcase.include?("total") || cell.downcase.include?("subtotal") || ignore_row
          ignore_row = true
        else
          cell_row << cell if (not (cell.nil? or cell.to_s.strip.empty?)) or not(cell_row.empty?)
        end
      end
      if !ignore_row
      # cuva header
        if table_start
          if not cell_row.empty?
            header = cell_row
            table_start = false
          end
        else
          # cuva redove
          rows << cell_row unless cell_row.empty?
        end
      end
      ignore_row = false
    end

    # dodeljuje vrednosti parametrima
    @header = header
    @rows = rows

    define_column_methods
  end


  # vraca niz redova umesto Table objekat
  def inspect
    rows
  end

  # pristup redu po indexu (t.row(0))
  def row(index)
    rows[index]
  end

  # pristup celiji/redu kockastim zagradama
  def [](arg1, arg2 = nil)
    # sa stringovnim nazivom
    if arg1.is_a?(String) && header.include?(arg1)
      # racuna index iz headera
      header_index = header.index(arg1)

      # bez indeksa reda
      if arg2 == nil
        return @cols[arg1] #rows.transpose[header_index]
      end

      # sa indeksom reda
      @cols[arg1][arg2]
      #rows[arg2][header_index]

    # sa brojevima
    elsif arg1.is_a?(Integer)

      # bez indeksa reda
      if arg2 == nil
        return rows[arg1]
      end

      # sa indeksom reda
      rows[arg1][arg2]
    else
      nil
    end
  end

  def []=(arg1, arg2, value)
    if arg1.is_a?(String)
      header_index = header.index(arg1)
      @rows[arg2][header_index] = value
      @cols[arg1].column[arg2] = value
    else
      @rows[arg1][arg2] = value
      @cols[header[arg2]].column[arg1] = value
    end
  end

  # each Enumerable
  def each (&block)
    rows.each do |row|
      row.each(&block)
    end
  end

  class Kolona < Tabela
    attr_accessor :column, :parent, :head

    def initialize(col, parent, head)
      @column = col
      @parent = parent
      @head = head
      define_cell_methods
    end

    def sum
      column.map(&:to_f).inject(:+)
    end

    def avg
      self.sum / column.size
    end

    def map(&block)
      column.map(&block)
    end

    def select(&block)
      column.select(&block)
    end

    def reduce(initial, &block)
      column.reduce(initial, &block)
    end

    def define_cell_methods
      column.each_with_index do |cell, i|
        define_singleton_method(cell) do
          parent.row(i)
        end
      end
    end

    def [](i)
      header_index = @parent.header.index(head)
      @parent[i][header_index]
    end

    def []=(i,value)
      header_index = @parent.header.index(head)
      @parent[i][header_index] = value
      @column[i] = value
    end

    def inspect
      column
    end
  end

  def define_column_methods
    cols = {}
    header.each_with_index do |column_name, i|
      formatted_column_name = column_name.split.map.with_index do |word, index|
        index.zero? ? word.downcase : word.capitalize
      end.join
      cols[column_name] = Kolona.new(rows.map { |row| row[i] }, self, column_name)
      define_singleton_method(formatted_column_name) do
        cols[column_name]
      end
    end
    @cols = cols
  end

  def copy
    duplicate = self.clone
    duplicate.rows = rows.map(&:clone)
    duplicate.header = header.map(&:clone)
    duplicate.cols = cols.clone
    duplicate
  end


  def +(other)
    # Proverava da li imaju iste headere
    unless self.header == other.header
      raise ArgumentError, 'Tabele nemaju iste headere'
    end

    # Kopira 1. tabelu
    result_table = self.copy

    # Dodaje redove iz 2. tabele
    other.rows.each do |e|
      result_table.rows << e
    end
    # Azurira listu kolona
    header.each do |head|
      other.cols[head].column.each do |e|
        result_table.cols[head].column << e
      end
    end

    result_table
  end

  # Brise red tabele
  def delete_row(row)
    index = rows.index(row)
    rows.delete_at(index) if index
  end

  # Brise iz kolone tabele
  def delete_from_col(arr, head)
    arr.each do |e|
      i = cols[head].column.index(e)
      cols[head].column.delete_at(i) if i
    end
  end

  # Oduzimanje tabela
  def -(other)
    # Proverava da li imaju iste headere
    unless header == other.header
      raise ArgumentError, 'Tabele nemaju iste headere'
    end

    # Kopira 1. tabelu
    result_table = self.copy
    # p result_table.cols
    # p result_table.rows
    # Oduzima redove iz 2. tabele
    other.rows.each do |row|
      result_table.delete_row(row)
    end

    # Azurira listu kolona
    header.each do |head|
      result_table.delete_from_col(other.cols[head].column, head)
    end

    result_table
  end
end


def main
  # Ucitavanje spreadsheet-a
  session = GoogleDrive::Session.from_config("config.json")
  # Tabela: https://docs.google.com/spreadsheets/d/1TelLaG54dxQ4do3Nb8WnuVkL9WWeAicnqs_wPNEhINE/edit?usp=sharing
  ws = session.spreadsheet_by_key("1TelLaG54dxQ4do3Nb8WnuVkL9WWeAicnqs_wPNEhINE").worksheets[0]

  # Kreiranje tabele
  t = Tabela.new(ws)

  print "\n"
  p "1. Biblioteka može da vrati dvodimenzioni niz sa vrednostima tabele"
  p t

  print "\n"
  p "2. Moguće je pristupati redu preko t.row(1), i pristup njegovim elementima po sintaksi niza."
  p t.row(1)

  print "\n"
  p "3. Mora biti implementiran Enumerable modul(each funkcija), gde se vraćaju sve ćelije unutar tabele, sa leva na desno."
  t.each do |x|
    p x
  end

  print "\n"
  p "4.  Biblioteka treba da vodi računa o merge-ovanim poljima"

  print "\n"
  p  "5. [ ] sintaksa mora da bude obogaćena tako da je moguće pristupati određenim vrednostima."
  p  "a) Biblioteka vraća celu kolonu kada se napravi upit t[“Prva Kolona”]"
  p t["Prva Kolona"]
  p "b) Biblioteka omogućava pristup vrednostima unutar kolone po sledećoj sintaksi t[“Prva Kolona”][1] za pristup drugom elementu te kolone"
  p t["Prva kolona"][1]
  p "c) Biblioteka omogućava podešavanje vrednosti unutar ćelije po sledećoj sintaksit[“Prva Kolona”][1]= 2556"
  t["Prva kolona"][1] = 2556
  p t["Prva kolona"]

  p "6. Biblioteka omogućava direktni pristup kolonama, preko istoimenih metoda."
  p "t.prvaKolona, t.drugaKolona, t.trecaKolona"
  p t.prvaKolona
  p "a) Subtotal/Average  neke kolone se može sračunati preko sledećih sintaksi t.prvaKolona.sum i t.prvaKolona.avg"
  p t.prvaKolona.sum
  p t.prvaKolona.avg
  p "b) Iz svake kolone može da se izvuče pojedinačni red na osnovu vrednosti jedne od ćelija. (smatraćemo da ta ćelija jedinstveno identifikuje taj red)"
  p t.prvaKolona.rn2831
  p "Kolona mora da podržava funkcije kao što su map, select,reduce. Naprimer: t.prvaKolona.map { |cell| cell+=1 }"
  p t.prvaKolona.map {|cell| cell.is_a?(Integer)? cell + 1: cell.to_i + 1}
  p t.prvaKolona.select {|cell| cell.to_f > 0}
  p t.prvaKolona.reduce(0) { |sum, num| sum + num.to_f }

  print "\n"
  p "7. Biblioteka prepoznaje ukoliko postoji na bilo koji način ključna reč total ili subtotal unutar sheet-a, i ignoriše taj red"
  p "Prvi spreadsheet sadrzi i total i subtotal red"

  print "\n"
  p "8. Moguce je sabiranje dve tabele, sve dok su im headeri isti. Npr t1+t2, gde svaka predstavlja, tabelu unutar jednog od worksheet-ova. Rezultat će vratiti novu tabelu gde su redovi(bez headera) t2 dodati unutar t1. (SQL UNION operacija)"
  # Napravi 2. tabelu iz drugog sheeta
  ws2 = session.spreadsheet_by_key("1TelLaG54dxQ4do3Nb8WnuVkL9WWeAicnqs_wPNEhINE").worksheets[1]
  t2 = Tabela.new(ws2)
  p t + t2

  print "\n"
  p "9. Moguce je oduzimanje dve tabele, sve dok su im headeri isti. Npr t1-t2, gde svaka predstavlja reprezentaciju jednog od worksheet-ova. Rezultat će vratiti novu tabelu gde su svi redovi iz t2 uklonjeni iz t1, ukoliko su identicni."
  p t - t2

  print "\n"
  p "10. Biblioteka prepoznaje prazne redove, koji mogu biti ubačeni izgleda radi"
  p "Tabela 't' sadrzi prazne redove. Oni su iskljuceni"
end

main()
