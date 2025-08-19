import h5py
import numpy as np
import matplotlib.pyplot as plt

filename = "tripolar_grid.h5"  # Change this if your file has a different name

data_dict = {}

with h5py.File(filename, "r") as f:
    print("Datasets found in file:")
    for name in f:
        arr = f[name][:]
        data_dict[name] = np.array(arr)
        print(f"  {name}: shape={arr.shape}, dtype={arr.dtype}")

# Example: access data as numpy arrays
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

#print("\nData shapes:")
#print(f"cell_center: {cell_center.shape if cell_center is not None else 'Not found'}")
#print(f"cell_scalar: {cell_scalar.shape if cell_scalar is not None else 'Not found'}")
#print(f"cell_vector: {cell_vector.shape if cell_vector is not None else 'Not found'}")
#print(f"node: {node.shape if node is not None else 'Not found'}")
#print(f"node_scalar: {node_scalar.shape if node_scalar is not None else 'Not found'}")
#print(f"node_vector: {node_vector.shape if node_vector is not None else 'Not found'}")
#print(f"x_face: {x_face.shape if x_face is not None else 'Not found'}")
#print(f"x_face_scalar: {x_face_scalar.shape if x_face_scalar is not None else 'Not found'}")
#print(f"x_face_vector: {x_face_vector.shape if x_face_vector is not None else 'Not found'}")
#print(f"y_face: {y_face.shape if y_face is not None else 'Not found'}")
#print(f"y_face_scalar: {y_face_scalar.shape if y_face_scalar is not None else 'Not found'}")
#print(f"y_face_vector: {y_face_vector.shape if y_face_vector is not None else 'Not found'}")
#print(f"z_face: {z_face.shape if z_face is not None else 'Not found'}")
#print(f"z_face_scalar: {z_face_scalar.shape if z_face_scalar is not None else 'Not found'}")
#print(f"z_face_vector: {z_face_vector.shape if z_face_vector is not None else 'Not found'}")    


z_slice = 0  # Example slice at z=0

def plot_scalar_field(name, array, location, z_slice, node):
    
    # Get x, y coordinates for z=0
    # cell_center shape: (nx, ny, nz, 3)
    #x = cell_center[:, :, z_slice, 0]
    #y = cell_center[:, :, z_slice, 1]
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
    #plt.show()
    plt.savefig(f"{name}_z_slice_{z_slice:04d}.png")

plot_scalar_field("cell_scalar", cell_scalar, cell_center, z_slice, node)

#if cell_center is not None and cell_scalar is not None:
#    nx, ny, nz = cell_scalar.shape[:3]
#    
#    # Get x, y coordinates for z=0
#    # cell_center shape: (nx, ny, nz, 3)
#    #x = cell_center[:, :, z_slice, 0]
#    #y = cell_center[:, :, z_slice, 1]
#    x = node[:, :, z_slice, 0]
#    y = node[:, :, z_slice, 1]
#    
#    # Scalar field at z=0
#    scalar_slice = cell_scalar[:, :, z_slice]
#    
#    plt.figure(figsize=(6, 5))
#    plt.pcolormesh(x, y, scalar_slice, shading='auto', edgecolors='k')
#    plt.colorbar(label='cell_scalar')
#    plt.xlabel('x')
#    plt.ylabel('y')
#    plt.title(f'cell_scalar at z={z_slice}')
#    plt.tight_layout()
#    #plt.show()
#    plt.savefig(f"cell_scalar_z_slice_{z_slice:04d}.png")


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

    #plt.gca().set_xticks(node[:, 0, z_slice, 0])
    #plt.gca().set_yticks(node[0, :, z_slice, 1])
    #plt.grid(True, which='both', linestyle='-', color='black')

    xticks = node[:, 0, z_slice, 0]
    yticks = node[0, :, z_slice, 1]

    for y in yticks: 
        plt.plot([x_min, x_max], [y, y], color='gray', linestyle='--', alpha=0.5)

    for x in xticks:
        plt.plot([x, x], [y_min, y_max], color='gray', linestyle='--', alpha=0.5)

    plt.xlabel('x')
    plt.ylabel('y')
    plt.title(f'{name} (u,v) at z={z_slice}')
    #plt.colorbar(label=f'{name} (u,v)')
    plt.tight_layout()
    #plt.show()
    plt.savefig(f"{name}_z_slice_{z_slice:04d}.png")



plot_vector_field("cell_vector", cell_vector, cell_center, z_slice, node)
plot_vector_field("node_vector", node_vector, node, z_slice, node)
plot_vector_field("x_face_vector", x_face_vector, x_face, z_slice, node)
plot_vector_field("y_face_vector", y_face_vector, y_face, z_slice, node)


def plot_scalar_x_slice(name, array, location, y_slice, z_slice, node):
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
plot_scalar_x_slice("cell_scalar", cell_scalar, cell_center, y_slice_index, z_slice_index, node)
plot_scalar_x_slice("node_scalar", node_scalar, node, y_slice_index, z_slice_index, node)
plot_scalar_x_slice("x_face_scalar", x_face_scalar, x_face, y_slice_index, z_slice_index, node)

#print('cell_scalar')
#print(cell_scalar[:,y_slice_index,z_slice_index])
#print('node_scalar')
#print(node_scalar[:,y_slice_index,z_slice_index])
#print('x_face_scalar')
#print(x_face_scalar[:,y_slice_index,z_slice_index])