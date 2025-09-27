#include <cstddef>
#include <map>
#include <memory>

#include <gtest/gtest.h>
#include <hdf5.h>

#include "geometry.h"
#include "cartesian_grid.h"

using namespace turbo;

TEST(CartesianGrid, Constructor) {

    // Simple unit cube geometry
    const double x_min = 0.0;
    const double x_max = 1.0;
    const double y_min = 0.0;
    const double y_max = 1.0;
    const double z_min = 0.0;
    const double z_max = 1.0;
    std::shared_ptr<CartesianGeometry> geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    // Construct with 2 cells in each direction
    const std::size_t n_cell_x = 2;
    const std::size_t n_cell_y = 4;
    const std::size_t n_cell_z = 8;
    CartesianGrid grid(geom, n_cell_x, n_cell_y, n_cell_z);

    // Check number of elements in each dimension as expected
    EXPECT_EQ(grid.NCell(),  n_cell_x * n_cell_y * n_cell_z);
    EXPECT_EQ(grid.NCellI(), n_cell_x);
    EXPECT_EQ(grid.NCellJ(), n_cell_y);
    EXPECT_EQ(grid.NCellK(), n_cell_z);

    const std::size_t n_node_x = n_cell_x + 1;
    const std::size_t n_node_y = n_cell_y + 1;
    const std::size_t n_node_z = n_cell_z + 1;
    EXPECT_EQ(grid.NNode(), n_node_x * n_node_y * n_node_z);
    EXPECT_EQ(grid.NNodeI(), n_node_x);
    EXPECT_EQ(grid.NNodeJ(), n_node_y);
    EXPECT_EQ(grid.NNodeK(), n_node_z);

    // Convenience functions for the common X,Y,Z notation
    EXPECT_EQ(grid.NCellX(), n_cell_x);
    EXPECT_EQ(grid.NCellY(), n_cell_y);
    EXPECT_EQ(grid.NCellZ(), n_cell_z);
    EXPECT_EQ(grid.NNodeX(), n_node_x);
    EXPECT_EQ(grid.NNodeY(), n_node_y);
    EXPECT_EQ(grid.NNodeZ(), n_node_z);

    // Passing an invalid number of cells, 0, to the constructor should throw an exception
    EXPECT_THROW(CartesianGrid grid(geom,        0, n_cell_y, n_cell_z), std::invalid_argument);
    EXPECT_THROW(CartesianGrid grid(geom, n_cell_x,        0, n_cell_z), std::invalid_argument);
    EXPECT_THROW(CartesianGrid grid(geom, n_cell_x, n_cell_y,        0), std::invalid_argument);

}

TEST(CartesianGrid, Valid_Indices) {

    // Simple unit cube geometry
    const double x_min = 0.0, x_max = 1.0;
    const double y_min = 0.0, y_max = 1.0;
    const double z_min = 0.0, z_max = 1.0;
    std::shared_ptr<CartesianGeometry> geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    // Grid with 2 cells in each direction
    const std::size_t n_cell_x = 2;
    const std::size_t n_cell_y = 2;
    const std::size_t n_cell_z = 2;
    CartesianGrid grid(geom, n_cell_x, n_cell_y, n_cell_z);

    // Check valid node indices
    for (std::size_t i = 0; i < grid.NNodeX(); ++i) {
        for (std::size_t j = 0; j < grid.NNodeY(); ++j) {
            for (std::size_t k = 0; k < grid.NNodeZ(); ++k) {
                EXPECT_TRUE(grid.ValidNode(i,j,k));
            }
        }
    }
    EXPECT_FALSE(grid.ValidNode(grid.NNodeX(), 0, 0));
    EXPECT_FALSE(grid.ValidNode(0, grid.NNodeY(), 0));
    EXPECT_FALSE(grid.ValidNode(0, 0, grid.NNodeZ()));

    // Check valid cell indices
    for (std::size_t i = 0; i < grid.NCellX(); ++i) {
        for (std::size_t j = 0; j < grid.NCellY(); ++j) {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k) {
                EXPECT_TRUE(grid.ValidCell(i,j,k));
            }
        }
    }
    EXPECT_FALSE(grid.ValidCell(grid.NCellX(), 0, 0));
    EXPECT_FALSE(grid.ValidCell(0, grid.NCellY(), 0));
    EXPECT_FALSE(grid.ValidCell(0, 0, grid.NCellZ()));

    // Check valid IFace indices
    for (std::size_t i = 0; i < grid.NNodeX(); ++i) {
        for (std::size_t j = 0; j < grid.NCellY(); ++j) {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k) {
                EXPECT_TRUE(grid.ValidIFace(i,j,k));
            }
        }
    }
    EXPECT_FALSE(grid.ValidIFace(grid.NNodeX(), 0, 0));
    EXPECT_FALSE(grid.ValidIFace(0, grid.NCellY(), 0));
    EXPECT_FALSE(grid.ValidIFace(0, 0, grid.NCellZ())); 

    // Check valid JFace indices
    for (std::size_t i = 0; i < grid.NCellX(); ++i) {
        for (std::size_t j = 0; j < grid.NNodeY(); ++j) {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k) {
                EXPECT_TRUE(grid.ValidJFace(i,j,k));
            }
        }
    }
    EXPECT_FALSE(grid.ValidJFace(grid.NCellX(), 0, 0));
    EXPECT_FALSE(grid.ValidJFace(0, grid.NNodeY(), 0));
    EXPECT_FALSE(grid.ValidJFace(0, 0, grid.NCellZ()));

    // Check valid KFace indices
    for (std::size_t i = 0; i < grid.NCellX(); ++i) {
        for (std::size_t j = 0; j < grid.NCellY(); ++j) {
            for (std::size_t k = 0; k < grid.NNodeZ(); ++k) {
                EXPECT_TRUE(grid.ValidKFace(i,j,k));
            }
        }
    }
    EXPECT_FALSE(grid.ValidKFace(grid.NCellX(), 0, 0));
    EXPECT_FALSE(grid.ValidKFace(0, grid.NCellY(), 0));
    EXPECT_FALSE(grid.ValidKFace(0, 0, grid.NNodeZ())); 

}

TEST(CartesianGrid, Grid_Locations) {

    // Simple unit cube geometry
    const double x_min = 0.0, x_max = 1.0;
    const double y_min = 0.0, y_max = 1.0;
    const double z_min = 0.0, z_max = 1.0;
    std::shared_ptr<CartesianGeometry> geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    // Grid with 2 cells in each direction
    const std::size_t n_cell_x = 2;
    const std::size_t n_cell_y = 2;
    const std::size_t n_cell_z = 2;
    CartesianGrid grid(geom, n_cell_x, n_cell_y, n_cell_z);

    // Check if out of bounds indices throw an exception
    EXPECT_THROW(grid.Node(3, 0, 0), std::out_of_range);
    EXPECT_THROW(grid.Node(0, 3, 0), std::out_of_range);
    EXPECT_THROW(grid.Node(0, 0, 3), std::out_of_range);

    // Map of valid node index to expected node position
    const std::map<const std::size_t, const double> index_to_node = {
        {0, 0.0},
        {1, 0.5},
        {2, 1.0}
    };

    // Map of valid cell index to expected cell center position
    const std::map<const std::size_t, const double> index_to_cell_center = {
        {0, 0.25},
        {1, 0.75},
    };

    // Check node positions
    for (std::size_t i = 0; i < grid.NNodeX(); ++i) {
        for (std::size_t j = 0; j < grid.NNodeY(); ++j) {
            for (std::size_t k = 0; k < grid.NNodeZ(); ++k) {
                auto node = grid.Node(i, j, k);
                auto expected_node = Grid::Point({index_to_node.at(i), index_to_node.at(j), index_to_node.at(k)});
                EXPECT_EQ(node, expected_node);
                //EXPECT_EQ(node.x, expected_node.x);
                //EXPECT_EQ(node.y, expected_node.y);
                //EXPECT_EQ(node.z, expected_node.z);
            }
        }
    }


    // Check cell center positions
    for (std::size_t i = 0; i < grid.NCellX(); ++i) {
        for (std::size_t j = 0; j < grid.NCellY(); ++j) {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k) {
                auto cell_center = grid.CellCenter(i, j, k);
                auto expected_cell_center = Grid::Point({index_to_cell_center.at(i), index_to_cell_center.at(j), index_to_cell_center.at(k)});
            }
        }
    }

    // Check XFace positions
    for (std::size_t i = 0; i < grid.NNodeX(); ++i) {
        for (std::size_t j = 0; j < grid.NCellY(); ++j) {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k) {
                auto x_face = grid.XFace(i, j, k);
                auto expected_x_face = Grid::Point({index_to_node.at(i), index_to_cell_center.at(j), index_to_cell_center.at(k)});
                EXPECT_EQ(x_face, expected_x_face);
            }
        }
    }

    // Check YFace positions
    for (std::size_t i = 0; i < grid.NCellX(); ++i) {
        for (std::size_t j = 0; j < grid.NNodeY(); ++j) {
            for (std::size_t k = 0; k < grid.NCellZ(); ++k) {
                auto y_face = grid.YFace(i, j, k);
                auto expected_y_face = Grid::Point({index_to_cell_center.at(i), index_to_node.at(j), index_to_cell_center.at(k)});
                EXPECT_EQ(y_face, expected_y_face);
            }
        }
    }

    // Check ZFace positions
    for (std::size_t i = 0; i < grid.NCellX(); ++i) {
        for (std::size_t j = 0; j < grid.NCellY(); ++j) {
            for (std::size_t k = 0; k < grid.NNodeZ(); ++k) {
                auto z_face = grid.ZFace(i, j, k);
                auto expected_z_face = Grid::Point({index_to_cell_center.at(i), index_to_cell_center.at(j), index_to_node.at(k)});
                EXPECT_EQ(z_face, expected_z_face);
            }
        }
    }

}

TEST(CartesianGrid, WriteHDF5) {

    // Simple unit cube geometry
    const double x_min = 0.0, x_max = 1.0;
    const double y_min = 0.0, y_max = 1.0;
    const double z_min = 0.0, z_max = 1.0;
    std::shared_ptr<CartesianGeometry> geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    // Grid with 2 cells in each direction
    const std::size_t n_cell_x = 2;
    const std::size_t n_cell_y = 2;
    const std::size_t n_cell_z = 2;
    CartesianGrid grid(geom, n_cell_x, n_cell_y, n_cell_z);

    // Write to HDF5 file
    {
        const std::string filename = "Test_Output_CartesianGrid_WriteHDF5_via_file_id.h5";
        const hid_t file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
        grid.WriteHDF5(file_id);
        H5Fclose(file_id);
    }
    {
        const std::string filename = "Test_Output_CartesianGrid_WriteHDF5_via_filename.h5";
        grid.WriteHDF5(filename);
    }
}