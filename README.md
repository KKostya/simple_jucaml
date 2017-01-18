# simple_jucaml
A very simple Jupyter kernel for OCaml

# Compilation
You'll need `Yojson`, `Nocrypto` and `ZMQ` bindings for OCaml.  It also relies
on `Core.Time` and `Core.Uuid` packages.

    opam install core
    opam install yojson
    opam install nocrypto
    opam install ZMQ

Native toplevel is not supported by OCaml, thus only bytecode compilation is possible.
    
    corebuild jucaml.byte

# Installation 
Check in which directories your Jupyter looks for kernels.

    python -c "import jupyter_client.kernelspec as j; print '\n'.join(j.KernelSpecManager().kernel_dirs)"
    
    > /home/user/.local/share/jupyter/kernels
    > /home/user/VirtualEnv/ipython/share/jupyter/kernels
    > /usr/local/share/jupyter/kernels
    > /usr/share/jupyter/kernels
    > /home/user/.ipython/kernels

Pick one of them and make a `jucaml` subdirectory there.
    
    mkdir -p /home/user/.local/share/jupyter/kernels/jucaml

Finally, create a `kernel.json` with a path to the executable.

    cat > /home/user/.local/share/jupyter/kernels/jucaml/kernel.json << EOF
    {
        "argv": ["$PWD/jucaml.byte", "{connection_file}"],
        "display_name": "JUcaml",
        "language": "OCaml"
    }
    EOF


