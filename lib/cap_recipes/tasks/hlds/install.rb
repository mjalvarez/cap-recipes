# @author Donovan Bray <donnoman@donovanbray.com>

Capistrano::Configuration.instance(true).load do

  namespace :hlds do 

    roles[:hlds]
    set :hlds_root, "/opt/gameserver"
    set(:hlds_source) {hlds_root}
    set :hlds_user, "tf2server"
    set :hlds_update_tool_url, "http://storefront.steampowered.com/download/hldsupdatetool.bin"
    set :hlds_game, "tf"
    set(:hlds_bindir) { "#{hlds_root}/orangebox"}
    set :hlds_init_erb, File.join(File.dirname(__FILE__),'hlds.init.erb')
    set :hlds_init_dest, '/etc/init.d/hlds'
    set :hlds_config_erb, File.join(File.dirname(__FILE__),'server.cfg.erb')
    set :hlds_motd_txt_erb, File.join(File.dirname(__FILE__),'motd.txt.erb')
    set :hlds_motd_text_txt_erb, File.join(File.dirname(__FILE__),'motd_text.txt.erb')
    set(:hlds_config_root) {"#{hlds_root}/orangebox/tf/cfg"}
    set(:hlds_config_server_cfg) {"#{hlds_config_root}/server.cfg"}
    set :hlds_mapcycle, %w(mvm_decoy mvm_coaltown mvm_mannworks)
    set(:hlds_parameters) {"-autoupdate -maxplayers 32 +map #{hlds_mapcycle.first}"}
    set :hlds_motd, "welcome"
    set :hlds_config_hostname, "TF2 Server"
    set :hlds_config_sv_contact, "Unset as of Yet"
    set :hlds_config_sv_region, "1"  # -1 is the world, 0 is USA east coast, 1 is USA west coast 2 south america, 3 europe, 4 asia, 5 australia, 6 middle east, 7 africa
    set(:hlds_config_rcon_password) {utilities.ask("rcon_password")}
    set :hlds_config_sv_password, nil # connect password
    set :hlds_config_tf_server_identity_account_id, nil
    set :hlds_config_tf_server_identity_token, nil

    task :install, :roles => :hlds do
      run "#{sudo} mkdir -p #{hlds_source} #{hlds_root}"
      utilities.adduser hlds_user, :system => true
      run "cd #{hlds_source} && #{sudo} wget --tries=2 -c --progress=bar:force #{hlds_update_tool_url} && #{sudo} chmod +x hldsupdatetool.bin"
      utilities.run_with_input "cd #{hlds_source} && #{sudo} ./hldsupdatetool.bin", /decline:/, "yes\n"
      tries = 0
      begin
        run "cd #{hlds_source} && #{sudo} ./steam"
      rescue
        tries += 1
        retry if tries <= 5
      end
      run "#{sudo} chown -R #{hlds_user}:#{hlds_user} #{hlds_root}"
    end

    task :setup, :roles => :hlds do
      utilities.sudo_upload_template hlds_init_erb, hlds_init_dest, :owner => "root:root", :mode => "700"
      utilities.sudo_upload_template hlds_config_erb, hlds_config_server_cfg, :owner => "#{hlds_user}:#{hlds_user}"
      utilities.sudo_upload_template hlds_motd_txt_erb, "#{hlds_bindir}/tf/motd.txt", :owner => "#{hlds_user}:#{hlds_user}"
      utilities.sudo_upload_template hlds_motd_text_txt_erb, "#{hlds_bindir}/tf/motd_text.txt", :owner => "#{hlds_user}:#{hlds_user}"
      put hlds_mapcycle.join("\n")+"\n", "/tmp/mapcycle.txt", :owner => "#{hlds_user}:#{hlds_user}"
      run "#{sudo} cp #{hlds_bindir}/tf/mapcycle.txt #{hlds_bindir}/tf/mapcycle.txt.`date +%s`"
      run "#{sudo} mv /tmp/mapcycle.txt #{hlds_bindir}/tf/mapcycle.txt"
    end

    task :update, :roles => :hlds do
      run "cd #{hlds_source} && #{sudo} ./steam -command update -game #{hlds_game} -dir #{hlds_root}"
      run "#{sudo} chown -R #{hlds_user}:#{hlds_user} #{hlds_root}"
    end

    %w(start stop restart).each do |t|
      task t.to_sym, :roles => :hlds do
        run "#{sudo} /etc/init.d/hlds #{t}"
      end
    end

  end
end