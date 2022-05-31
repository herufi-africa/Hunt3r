class Httpx
  def self.check_domains
    subdomains = []

    file = File.read("#{OPTIONS[:output]}/naabu.json")
    data = JSON.parse(file)

    thread_pool = ThreadPool.new
    thread_pool.start

    urls = []
    data.each do |host, infos|
      thread_pool.schedule do
        httpx_ports = infos['ports'].join(',')
        httpx = `echo #{host} | httpx -silent -sc -cl -location -title -td -cname -cdn -ports #{httpx_ports} -json`
        next if httpx.empty?

        httpx.chomp!
        results = httpx.split("\n")

        results.each do |result|
          result_json = JSON.parse(result)
          url = result_json['url']

          # Allows not to pollute the recon with useless domains
          # Ex http://www.domain.tld 302 to https://www.domain.tld
          next if url.start_with?('http://') && url.match?(%r{https://(www\.)?#{host}(:443)?/?})
          next if url.match?(%r{https://.*:80})

          url.sub!(':443', '')
          url.sub!(':80', '')

          technologies = []

          begin
            wappalyzer = JSON.load(`node /root/Tools/wappalyzer/src/drivers/npm/cli.js #{url}`)
            wappalyzer['technologies'].each do |technology|
              technologies << technology['name']
            end
          rescue
          end

          subdomain = {
            url: url,
            infos: {
              title: result_json['title'],
              status_code: result_json['status-code'],
              content_length: result_json['content-length'],
              location: result_json['location'],
              technologies: technologies,
              ip: infos['ip'],
              cname: result_json.dig('cnames', 0),
              cdn: result_json['cdn-name'],
              ports: infos['ports'],
              body_hash: result_json.dig('hashes', 'body-sha256')
            }
          }

          urls << url
          subdomains << subdomain
        end
      end
    end

    sleep(5) until thread_pool.inactive?

    File.open("#{OPTIONS[:output]}/httpx.txt", 'w+') do |f|
      f.puts(urls)
    end

    if File.zero?("#{OPTIONS[:output]}/httpx.txt")
      InteractDashboard.send_notification('danger', "ScanID : #{OPTIONS[:scan_id]} | The file httpx.txt is empty")
      InteractDashboard.delete_server
    end

    InteractDashboard.send_subdomain(subdomains)
  end
end
