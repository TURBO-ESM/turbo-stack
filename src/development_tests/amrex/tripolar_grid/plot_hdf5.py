import argparse
import h5py
import numpy as np
import matplotlib.pyplot as plt

parser = argparse.ArgumentParser(description="Plot data from HDF5 file")
parser.add_argument("filename", type=str, help="Path to the HDF5 file")
args = parser.parse_args()

data_dict = {}

with h5py.File(args.filename, "r") as f:
    print("Datasets found in file:")
    for name in f:
        arr = f[name][:]
        data_dict[name] = np.array(arr)
        print(f"  {name}: shape={arr.shape}, dtype={arr.dtype}")

# Get data as numpy arrays
cell_center = data_dict.get("cell_center")
cell_scalar = data_dict.get("cell_scalar")
cell_vector = data_dict.get("cell_vector")

node = data_dict.get("node")
node_scalar = data_dict.get("node_scalar")
node_vector = data_dict.get("node_vector")

x_face = data_dict.get("x_face")
x_face_scalar = data_dict.get("x_face_scalar")
x_face_vector = data_dict.get("x_face_vector")

y_face = data_dict.get("y_face")
y_face_scalar = data_dict.get("y_face_scalar")
y_face_vector = data_dict.get("y_face_vector")

z_face = data_dict.get("z_face")
z_face_scalar = data_dict.get("z_face_scalar")
z_face_vector = data_dict.get("z_face_vector")

def plot_cell_scalar_field(name, array, z_slice, node):
    
    # Get x, y coordinates of the nodes.
    x = node[:, :, z_slice, 0]
    y = node[:, :, z_slice, 1]

    # Scalar field at z=0
    scalar_slice = array[:, :, z_slice]
    
    plt.figure(figsize=(6, 5))
    plt.pcolormesh(x, y, scalar_slice, shading='auto', edgecolors='k')
    plt.colorbar(label=f'{name}')
    plt.xlabel('x')
    plt.ylabel('y')
    plt.title(f'{name} at z={z_slice}')
    plt.tight_layout()
    plt.savefig(f"{name}_z_slice_{z_slice:04d}.png")

z_slice_index = 0
plot_cell_scalar_field("cell_scalar", cell_scalar , z_slice_index, node)

def plot_vector_field(name, array, location, z_slice, node):

    x = location[:, :, z_slice, 0]
    y = location[:, :, z_slice, 1]
    z = location[:, :, z_slice, 2]

    u = array[:, :, z_slice, 0]
    v = array[:, :, z_slice, 1]
    w = array[:, :, z_slice, 2]

    plt.figure(figsize=(6, 5))
    plt.quiver(x, y, u, v)

    x_min = np.min(node[:, :, :, 0])
    x_max = np.max(node[:, :, :, 0])
    y_min = np.min(node[:, :, :, 1])
    y_max = np.max(node[:, :, :, 1])
    z_min = np.min(node[:, :, :, 2])
    z_max = np.max(node[:, :, :, 2])

    Lx = x_max - x_min
    Ly = y_max - y_min
    padding = 0.1
    plt.xlim(x_min-padding*Lx, x_max+padding*Lx)
    plt.ylim(y_min-padding*Ly, y_max+padding*Ly)
    #plt.xlim(x_min, x_max)
    #plt.ylim(y_min, y_max)

    xticks = node[:, 0, z_slice, 0]
    yticks = node[0, :, z_slice, 1]
    for y in yticks: 
        plt.plot([x_min, x_max], [y, y], color='gray', linestyle='--', alpha=0.5)
    for x in xticks:
        plt.plot([x, x], [y_min, y_max], color='gray', linestyle='--', alpha=0.5)

    plt.xlabel('x')
    plt.ylabel('y')
    plt.title(f'{name} (u,v) at z={z_slice}')
    plt.tight_layout()
    plt.savefig(f"{name}_z_slice_{z_slice:04d}.png")

plot_vector_field("cell_vector",   cell_vector,   cell_center, z_slice_index, node)
plot_vector_field("node_vector",   node_vector,   node,        z_slice_index, node)
plot_vector_field("x_face_vector", x_face_vector, x_face,      z_slice_index, node)
plot_vector_field("y_face_vector", y_face_vector, y_face,      z_slice_index, node)

def plot_scalar_x_line(name, array, location, y_slice, z_slice, node):
    x = location[:, y_slice, z_slice, 0]

    slice_values = array[:, y_slice, z_slice]

    plt.figure(figsize=(6, 5))

    plt.plot(x, slice_values, marker='o', linestyle='-')

    x_min = np.min(node[:, :, :, 0])
    x_max = np.max(node[:, :, :, 0])
    Lx = x_max - x_min
    padding = 0.1
    plt.xlim(x_min-padding*Lx, x_max+padding*Lx)

    #plt.gca().set_xticks(node[:, y_slice, z_slice, 0])

    plt.xlabel('x')
    plt.ylabel(name)
    plt.title(f'{name} at j={y_slice} k={z_slice}')
    plt.tight_layout()
    #plt.show()
    plt.savefig(f"{name}_y_{y_slice:04d}_z_{z_slice:04d}.png")

y_slice_index = 0
z_slice_index = 0
plot_scalar_x_line("cell_scalar", cell_scalar, cell_center, y_slice_index, z_slice_index, node)
plot_scalar_x_line("node_scalar", node_scalar, node, y_slice_index, z_slice_index, node)
plot_scalar_x_line("x_face_scalar", x_face_scalar, x_face, y_slice_index, z_slice_index, node)
