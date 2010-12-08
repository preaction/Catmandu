use Plack::Builder;
use Module::Search;

builder {

    mount "/" => builder {
        enable "Plack::Middleware::Static" ,
            path => qr{^/(images|js|css)/} , root => './htdocs/';
        Module::Search->to_app;
    };
};