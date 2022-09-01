function handler(event) {
    var response = event.response;
    var headers = response.headers;

    // Force HSTS and Change server Name.
    headers['server'] = {value: "Nginx"};
    headers['strict-transport-security'] = {value: "max-age=63072000; includeSubdomains; preload"};

    // Set HTTP security headers
    if (headers['content-type'] && headers['content-type'].value == 'text/html') {
        headers['content-security-policy'] = {
            value: "require-trusted-types-for 'script'; default-src 'none'; img-src 'self'; " +
                "script-src https:  'sha256-ws7am3OYlM2dhKH1jeB5ItmdGlQTRfQSdT3llz8nd8M=' 'sha256-sI9S14ompKIA+MyPxQ84ucUq3p+JKTvKD3E8qfKQvcc=' 'strict-dynamic' 'unsafe-inline'; " +
                "script-src-elem 'self' https://www.googletagmanager.com 'sha256-SjP4DKbgzKbSIJ6khH2h4w68+MPNPvsOtujPhgl/Mh4=' 'sha256-4CQqINfLuP3nhL220h322geGof5a8+vo3u5unLM/2rw='; " +
                "style-src 'self' https://fonts.googleapis.com; " +
                "font-src 'self' https://fonts.gstatic.com; " +
                "connect-src https://*.google-analytics.com https://www.googletagmanager.com; " +
                "form-action 'none'; frame-ancestors 'none'; base-uri 'self'; object-src 'none'"
        };
        headers['x-content-type-options'] = {value: 'nosniff'};
        headers['x-frame-options'] = {value: 'DENY'};
        headers['x-xss-protection'] = {value: '1; mode=block'};
    }
    ;

    // Return the response to viewers
    return response;
}