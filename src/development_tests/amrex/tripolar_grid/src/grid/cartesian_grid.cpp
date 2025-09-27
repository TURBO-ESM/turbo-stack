#include <cstddef>
#include <stdexcept>
#include <string>
#include <vector>

#include "cartesian_grid.h"
#include "geometry.h"

namespace turbo {

CartesianGrid::CartesianGrid(const std::shared_ptr<CartesianGeometry>& geometry, 
                  std::size_t n_cell_x, std::size_t n_cell_y, std::size_t n_cell_z)
    : geometry_(geometry), dx_(0.0), dy_(0.0), dz_(0.0), n_cell_x_(n_cell_x), n_cell_y_(n_cell_y), n_cell_z_(n_cell_z) {

    if (!geometry_) {
        throw std::invalid_argument("Null geometry pointer passed to CartesianGrid constructor.");
    }

    if (n_cell_x == 0 || n_cell_y == 0 || n_cell_z == 0) {
        throw std::invalid_argument("Number of cells in each direction must be greater than zero.");
    }

    dx_ = static_cast<double>(geometry_->LX()) / n_cell_x_;
    dy_ = static_cast<double>(geometry_->LY()) / n_cell_y_;
    dz_ = static_cast<double>(geometry_->LZ()) / n_cell_z_;
}

std::size_t CartesianGrid::NCell(void) const noexcept { return NCellX() * NCellY() * NCellZ(); }
std::size_t CartesianGrid::NCellI() const noexcept { return n_cell_x_; }
std::size_t CartesianGrid::NCellJ() const noexcept { return n_cell_y_; }
std::size_t CartesianGrid::NCellK() const noexcept { return n_cell_z_; }

std::size_t CartesianGrid::NNode(void) const noexcept { return NNodeX() * NNodeY() * NNodeZ(); }
std::size_t CartesianGrid::NNodeI() const noexcept { return n_cell_x_ + 1; }
std::size_t CartesianGrid::NNodeJ() const noexcept { return n_cell_y_ + 1; }
std::size_t CartesianGrid::NNodeK() const noexcept { return n_cell_z_ + 1; }

CartesianGrid::Point CartesianGrid::Node(const Index i, const Index j, const Index k) const {
    if (!ValidNode(i,j,k)) {
        throw std::out_of_range("Node index out of bounds");
    }
    return Point({geometry_->XMin() + i * dx_, geometry_->YMin() + j * dy_, geometry_->ZMin() + k * dz_});
}

CartesianGrid::Point CartesianGrid::CellCenter(const Index i, const Index j, const Index k) const {
    if (!ValidCell(i,j,k)) {
        throw std::out_of_range("Cell index out of bounds");
    }
    return Node(i,j,k) + Point{dx_*0.5, dy_*0.5, dz_*0.5};
}

CartesianGrid::Point CartesianGrid::IFace(const Index i, const Index j, const Index k) const {
    if (!ValidIFace(i,j,k)) {
        throw std::out_of_range("IFace index out of bounds");
    }
    return Node(i,j,k) + Point{0.0, dy_*0.5, dz_*0.5};
}

CartesianGrid::Point CartesianGrid::JFace(const Index i, const Index j, const Index k) const {
    if (!ValidJFace(i,j,k)) {
        throw std::out_of_range("JFace index out of bounds");
    }
    return Node(i,j,k) + Point{dx_*0.5, 0.0, dz_*0.5};
}

CartesianGrid::Point CartesianGrid::KFace(const Index i, const Index j, const Index k) const {
    if (!ValidKFace(i,j,k)) {
        throw std::out_of_range("KFace index out of bounds");
    }
    return Node(i,j,k) + Point{dx_*0.5, dy_*0.5, 0.0};
}

std::size_t CartesianGrid::NNodeX(void) const noexcept { return NNodeI(); }
std::size_t CartesianGrid::NNodeY(void) const noexcept { return NNodeJ(); }
std::size_t CartesianGrid::NNodeZ(void) const noexcept { return NNodeK(); }
std::size_t CartesianGrid::NCellX() const noexcept { return NCellI(); }
std::size_t CartesianGrid::NCellY() const noexcept { return NCellJ(); }
std::size_t CartesianGrid::NCellZ() const noexcept { return NCellK(); }
CartesianGrid::Point CartesianGrid::XFace(const Index i, const Index j, const Index k) const { return IFace(i,j,k); }
CartesianGrid::Point CartesianGrid::YFace(const Index i, const Index j, const Index k) const { return JFace(i,j,k); }
CartesianGrid::Point CartesianGrid::ZFace(const Index i, const Index j, const Index k) const { return KFace(i,j,k); }

void CartesianGrid::WriteHDF5(const std::string& filename) const {
    hid_t file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT); 
    if (file_id < 0) {
        throw std::runtime_error("Failed to open HDF5 file");
    }
    WriteHDF5(file_id);
    H5Fclose(file_id);
}

void CartesianGrid::WriteHDF5(const hid_t file_id) const {
    if (file_id < 0) {
        throw std::runtime_error("Invalid HDF5 file_id passed to WriteHDF5.");
    }

    // Helper lambda for writing the grid points for a given location (cell center, node, face, etc)
    auto write_grid_point_dataset = [file_id](const std::string& name, int nx, int ny, int nz, auto&& location_func) {
        const int n_component = 3; // Assuming here grid points will always have three components: x,y,z
        std::vector<hsize_t> dims = {static_cast<hsize_t>(nx), static_cast<hsize_t>(ny), static_cast<hsize_t>(nz), static_cast<hsize_t>(n_component)};
        const hid_t dataspace_id = H5Screate_simple(dims.size(), dims.data(), NULL);
        const hid_t dataset_id = H5Dcreate(file_id, name.c_str(), H5T_NATIVE_DOUBLE, dataspace_id, H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
        std::vector<double> data(nx * ny * nz * n_component);
        std::size_t idx = 0;
        for (int i = 0; i < nx; ++i) {
            for (int j = 0; j < ny; ++j) {
                for (int k = 0; k < nz; ++k) {
                    const Grid::Point location = location_func(i, j, k);
                    data[idx++] = location.x;
                    data[idx++] = location.y;
                    data[idx++] = location.z;
                }
            }
        }
        H5Dwrite(dataset_id, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, data.data());
        H5Dclose(dataset_id);
        H5Sclose(dataspace_id);
    };

    // Write datasets for all the grid stagger locations
    write_grid_point_dataset("cell_center", NCellX(), NCellY(), NCellZ(), [this](const Index i, const Index j, const Index k) { return this->CellCenter(i,j,k); });
    write_grid_point_dataset("node",        NNodeX(), NNodeY(), NNodeZ(), [this](const Index i, const Index j, const Index k) { return this->Node(i,j,k); });
    write_grid_point_dataset("x_face",      NNodeX(), NCellY(), NCellZ(), [this](const Index i, const Index j, const Index k) { return this->XFace(i,j,k); });
    write_grid_point_dataset("y_face",      NCellX(), NNodeY(), NCellZ(), [this](const Index i, const Index j, const Index k) { return this->YFace(i,j,k); });
    write_grid_point_dataset("z_face",      NCellX(), NCellY(), NNodeZ(), [this](const Index i, const Index j, const Index k) { return this->ZFace(i,j,k); });
}

bool CartesianGrid::ValidNode(const Index i, const Index j, const Index k) const noexcept {
    return (i >= 0 && i < NNodeX() && j >= 0 && j < NNodeY() && k >= 0 && k < NNodeZ());
}

bool CartesianGrid::ValidCell(const Index i, const Index j, const Index k) const noexcept {
    return (i >= 0 && i < NCellX() && j >= 0 && j < NCellY() && k >= 0 && k < NCellZ());
}

bool CartesianGrid::ValidIFace(const Index i, const Index j, const Index k) const noexcept {
    return (i >= 0 && i < NNodeX() && j >= 0 && j < NCellY() && k >= 0 && k < NCellZ());
}

bool CartesianGrid::ValidJFace(const Index i, const Index j, const Index k) const noexcept {
    return (i >= 0 && i < NCellX() && j >= 0 && j < NNodeY() && k >= 0 && k < NCellZ());
}

bool CartesianGrid::ValidKFace(const Index i, const Index j, const Index k) const noexcept {
    return (i >= 0 && i < NCellX() && j >= 0 && j < NCellY() && k >= 0 && k < NNodeZ());
}

bool CartesianGrid::ValidXFace(const Index i, const Index j, const Index k) const noexcept { return ValidIFace(i,j,k); }
bool CartesianGrid::ValidYFace(const Index i, const Index j, const Index k) const noexcept { return ValidJFace(i,j,k); }
bool CartesianGrid::ValidZFace(const Index i, const Index j, const Index k) const noexcept { return ValidKFace(i,j,k); }

} // namespace turbo
