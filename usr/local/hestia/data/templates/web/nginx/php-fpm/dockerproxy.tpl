#=========================================================================#
# Default Web Domain Template                                             #
# DO NOT MODIFY THIS FILE! CHANGES WILL BE LOST WHEN REBUILDING DOMAINS   #
# https://docs.hestiacp.com/admin_docs/web.html#how-do-web-templates-work #
#=========================================================================#

server {
    listen      %ip%:80;
    server_name %domain_idn% %alias_idn%;
        
    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;



location / {
        proxy_read_timeout 300;

        proxy_set_header  X-Real-IP  "$remote_addr";

        proxy_set_header  X-Forwarded-For "$proxy_add_x_forwarded_for";
        proxy_set_header Host "$http_host";
	proxy_set_header X-Forwarded-Proto $scheme;

       
        proxy_max_temp_file_size 0;

        proxy_pass http://127.0.0.1:8888;
        proxy_ssl_server_name on;
        proxy_ssl_verify off;

        access_log     /var/log/%web_system%/domains/%domain%.log combined;
        access_log     /var/log/%web_system%/domains/%domain%.bytes bytes;

    }



    location /error/ {
        alias   %home%/%user%/web/%domain%/document_errors/;
    }

    location @fallback {
        proxy_pass      http://%ip%:%web_port%;
    }

    location ~ /\.(?!well-known\/|file) {
       deny all; 
       return 404;
    }

    include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}

