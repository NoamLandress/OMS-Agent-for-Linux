module MongoStatModule

  class MongoStat
    require_relative 'oms_common'

    # sample mongostat record
    #$ mongostat --all
    # insert query update delete getmore command flushes mapped  vsize   res non-mapped faults qr|qw ar|aw netIn netOut conn     time
    # *0    *0     *0     *0       0     2|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  158b    20k    2 16:24:07
    # *0    *0     *0     *0       0     2|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  158b    20k    2 16:24:08
    # *0    *0     *0     *0       0     3|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  212b    20k    2 16:24:09
    # *0    *0     *0     *0       0     2|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  158b    20k    2 16:24:10
    # *0    *0     *0     *0       0     3|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  212b    20k    2 16:24:11
    # *0    *0     *0     *0       0     2|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  158b    20k    2 16:24:12
    # *0    *0     *0     *0       0     3|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  216b    20k    2 16:24:13
    # *0    *0     *0     *0       0     3|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  212b    20k    2 16:24:14
    # *0    *0     *0     *0       0     2|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  158b    20k    2 16:24:15
    # *0    *0     *0     *0       0     3|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  212b    20k    2 16:24:16
    # insert query update delete getmore command flushes mapped  vsize   res non-mapped faults qr|qw ar|aw netIn netOut conn     time
    # *0    *0     *0     *0       0     2|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  158b    20k    2 16:24:17
    # *0    *0     *0     *0       0     2|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  158b    20k    2 16:24:18
    # *0    *0     *0     *0       0     3|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  212b    20k    2 16:24:19
    # *0    *0     *0     *0       0     2|0       0  80.0M 358.0M 25.0M     278.0M      0   0|0   0|0  158b    20k    2 16:24:20

    def transform_data(record)
      arr = record.split
      if record.start_with?('insert')
        #@counters saves the state of the counters as the counternames get printed at fixed intervals
        #reset values to [] when counter names are reset
        @counters = arr
        @values = []
      else
        @values = arr
      end

      if @values and @values.length > 0
        rec = Hash[@counters.zip @values]
        transformed_rec = {}
        begin
          transformed_rec["Insert Operations/sec"] = rec["insert"].delete("*") 
          transformed_rec["Query Operations/sec"] = rec["query"].delete("*")
          transformed_rec["Update Operations/sec"] = rec["update"].delete("*")
          transformed_rec["Delete Operations/sec"] = rec["delete"].delete("*")
          transformed_rec["Total Data Mapped (MB)"] = rec["mapped"].delete("M")
          transformed_rec["Virtual Memory Process Usage (MB)"] = rec["vsize"].delete("M")
          transformed_rec["Resident Memory Process Usage (MB)"] = rec["res"].delete("M") 
          transformed_rec["Get More Operations/sec"] = rec["getmore"]
          transformed_rec["Page Faults/sec"] = rec["faults"]
          transformed_rec["Total Open Connections"] = rec["conn"]
          transformed_rec["Replication Status"] = rec["repl"]
          transformed_rec["Network In (Bytes)"] = to_bytes(rec["netIn"])
          transformed_rec["Network Out (Bytes)"] = to_bytes(rec["netOut"])

          ar, aw = rec["ar|aw"].split("|")
          transformed_rec["Active Clients (Read)"] = ar
          transformed_rec["Active Clients (Write)"] = aw

          qr, qw = rec["qr|qw"].split("|")
          transformed_rec["Queue Length (Read)"] = qr
          transformed_rec["Queue Length (Write)"] = qw

          command = rec["command"]
          if command.include?("|")
            local, replicated = command.split("|")
            transformed_rec["Local Commands/sec"] = local
            transformed_rec["Replicated Commands/sec"] = replicated
          else
            transformed_rec["Commands/sec"] = command 
          end

          #version >= 3 rec has the counternames locked, dirty, used, non-mapped, flushes
          transformed_record["% Time Global Write Lock"] = rec["locked"] if rec.has_key?("locked")
          transformed_record["% WiredTiger Dirty Byte Cache"] = rec["dirty"]  if rec.has_key?("dirty")
          transformed_record["% WiredTiger Cache in Use"] = rec["used"] if rec.has_key?("used")
          if rec.has_key?("non-mapped")
            transformed_rec["Total Virtual Memory (MB)"] = rec["non-mapped"].delete("M")
          end
          if rec.has_key?("flushes")
            version = get_mongostat_version
            transformed_rec["WiredTiger Checkpoints Triggered"] = rec["flushes"] if version >= 3.2
            transformed_rec["Fsync Operations/sec"] = rec["flushes"] if version < 3.2
          end

          #version >=3.2 has the counternames lr|lw, lrt|lwt
          if rec.has_key?("lr|lw")
            lr, lw = rec["lr|lw"].split("|")
            transformed_rec["% Read Lock Acquisition Time"] = lr
            transformed_rec["% Write Lock Acquisition Time"] = lw
          end
          if rec.has_key?("lrt|lwt")
            lrt, lwt = rec["lrt|let"].split("|")
            transformed_rec["Avg. Read Lock Acquisition Time (ms)"] = lrt
            transformed_rec["Avg. Write Lock Acquisition Time (ms)"] = lwt
          end
        rescue => e
          $log.warn e.to_s
        end
 
        dataitems = {}       
        dataitems["Timestamp"] = OMS::Common.format_time(Time.now.to_f)
        dataitems["Host"] = OMS::Common.get_hostname
        dataitems["ObjectName"] = "MongoDB"
        collections = []

        transformed_rec.each { |k,v|
          if v.nil? or v == "nil"
            OMS::Log.warn_once("Dropping null value for counter #{k}")
          else
            counter_pair = {"CounterName" => k, "Value" => v} 
            collections.push(counter_pair) 
          end
        }
        dataitems["Collections"] = collections       
                  
        return dataitems
      end
    end

    def get_mongostat_version
      begin
        version = (%x(mongostat --version)).match(/(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)/)
        return (version["major"] + '.' + version["minor"]).to_f
      rescue => e
        $log.error e.to_s
      end
    end

    def to_bytes(val)
      num = val.match(/\d+\.?\d*/)[0].to_f
      case val[-1]
      when "k"
        num*1024
      when "M"
        num*(1024 ** 2)
      when "G"
        num*(1024 ** 3)
      when "T"
        num*(1024 ** 4)
      else
        num
      end
    end

   def transform_and_wrap(record)
     return nil if record.to_s.empty?

     data_items = transform_data(record)
     if (!data_items.nil? and data_items.size>0)
       wrapper = {
          "DataType"=>"LINUX_PERF_BLOB",
          "IPName"=>"LogManagement",
          "DataItems"=>[data_items]
        }
       return wrapper
     else
       return nil 
     end
   end

  end
end

