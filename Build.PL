use Module::Build;

Module::Build->new( module_name => 'Class::AlzaboWrapper',
                    license  => 'perl',
                    requires => { 'Alzabo' => 0,
                                  'Params::Validate' => 0,
                                  'Exception::Class' => 0,
                                },
                  )->create_build_script;
