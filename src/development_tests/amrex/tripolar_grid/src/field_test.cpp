#include <gtest/gtest.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include "geometry.h"
#include "grid.h"
#include "field.h"

using namespace turbo;

//---------------------------------------------------------------------------//
// Define a global test environment for AMReX
//---------------------------------------------------------------------------//
class AmrexEnvironment : public ::testing::Environment {
public:
    void SetUp() override {
        int argc = 1;
        char arg0[] = "test";
        char* argv_array[] = { arg0, nullptr };
        char** argv = argv_array;
        amrex::Initialize(argc, argv);
        std::cout << "AmrexEnvironment SetUp called\n";
    }
    void TearDown() override {
        amrex::Finalize();
        std::cout << "AmrexEnvironment TearDown called\n";
    }
};

::testing::Environment* const amrex_env = ::testing::AddGlobalTestEnvironment(new AmrexEnvironment());


//---------------------------------------------------------------------------//
// Define a test fixture for field container tests
//---------------------------------------------------------------------------//
class FieldContainerTest : public ::testing::Test {
protected:
  void SetUp() override {
    double x_min = 0.0;
    double x_max = 1.0;
    double y_min = 0.0;
    double y_max = 1.0;
    double z_min = 0.0;
    double z_max = 1.0;
    geom = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

    std::size_t n_cell_x = 2;
    std::size_t n_cell_y = 3;
    std::size_t n_cell_z = 4;
    grid = std::make_shared<CartesianGrid>(geom, n_cell_x, n_cell_y, n_cell_z);

    //fields = FieldContainer(grid);
  }

  //double x_min, x_max, y_min, y_max, z_min, z_max;
  //std::size_t n_cell_x, n_cell_y, n_cell_z;
  std::shared_ptr<CartesianGeometry> geom;
  std::shared_ptr<CartesianGrid> grid;
  //FieldContainer fields;
};

TEST_F(FieldContainerTest, Constructor) {
  FieldContainer fields(grid);

  {
    std::shared_ptr<Grid> grid_null_ptr = nullptr;
    EXPECT_THROW(FieldContainer field(grid_null_ptr), std::invalid_argument);
  }

}

TEST_F(FieldContainerTest, AddField) {

  FieldContainer fields(grid);

  // One off helper function to convert FieldLocation to string for naming fields
  auto FieldLocationToString = [](FieldLocation field_location) -> std::string {
    switch (field_location) {
      case FieldLocation::Nodal:        return "Nodal";
      case FieldLocation::CellCentered: return "CellCentered";
      case FieldLocation::IFace:        return "IFace";
      case FieldLocation::JFace:        return "JFace";
      case FieldLocation::KFace:        return "KFace";
      default: throw std::invalid_argument("FieldContainer:: Invalid FieldLocation specified.");
    }
  };

  for (std::size_t n_component : {1,3}) {
    for (std::size_t n_ghost : {0,1,2}) {
      for (const FieldLocation field_location : {FieldLocation::Nodal, FieldLocation::CellCentered, FieldLocation::IFace, FieldLocation::JFace, FieldLocation::KFace}) {

        std::string field_name = "field_" + FieldLocationToString(field_location) + "_ncomp_" + std::to_string(n_component) + "_nghost_" + std::to_string(n_ghost);
        auto mf = fields.AddField(field_name, field_location, n_component, n_ghost);

        EXPECT_TRUE(mf != nullptr);
        EXPECT_TRUE(mf->ok());
        EXPECT_EQ(mf->nComp(), n_component);
        EXPECT_EQ(mf->nGrow(), n_ghost);

        // Get the box that covers the entire MultiFab
        const amrex::Box& box = mf->boxArray().minimalBox();

        // For each field location, check the amrex indexing in each direction and the box size is correct
        switch (field_location)
        {
          case FieldLocation::Nodal:
            EXPECT_TRUE(mf->is_nodal(0));
            EXPECT_TRUE(mf->is_nodal(1));
            EXPECT_TRUE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NNodeI(), grid->NNodeJ(), grid->NNodeK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NNodeI()-1, grid->NNodeJ()-1, grid->NNodeK()-1));
            break;
          case FieldLocation::CellCentered:
            EXPECT_FALSE(mf->is_nodal(0));
            EXPECT_FALSE(mf->is_nodal(1));
            EXPECT_FALSE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NCellI(), grid->NCellJ(), grid->NCellK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NCellI()-1, grid->NCellJ()-1, grid->NCellK()-1));
            break;
          case FieldLocation::IFace:
            EXPECT_TRUE(mf->is_nodal(0));
            EXPECT_FALSE(mf->is_nodal(1));
            EXPECT_FALSE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NNodeI(), grid->NCellJ(), grid->NCellK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NNodeI()-1, grid->NCellJ()-1, grid->NCellK()-1));
            break;
          case FieldLocation::JFace:
            EXPECT_FALSE(mf->is_nodal(0));
            EXPECT_TRUE(mf->is_nodal(1));
            EXPECT_FALSE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NCellI(), grid->NNodeJ(), grid->NCellK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NCellI()-1, grid->NNodeJ()-1, grid->NCellK()-1));
            break;
          case FieldLocation::KFace:
            EXPECT_FALSE(mf->is_nodal(0));
            EXPECT_FALSE(mf->is_nodal(1));
            EXPECT_TRUE(mf->is_nodal(2));
            EXPECT_EQ(box.length(),   amrex::IntVect(grid->NCellI(), grid->NCellJ(), grid->NNodeK()));
            EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
            EXPECT_EQ(box.bigEnd(),   amrex::IntVect(grid->NCellI()-1, grid->NCellJ()-1, grid->NNodeK()-1));
            break;
          default:
              throw std::invalid_argument("FieldContainer:: Invalid FieldLocation specified.");
        }   

        // Test adding a field with a duplicate name
        EXPECT_THROW(fields.AddField(field_name, FieldLocation::Nodal, n_component, n_ghost), std::invalid_argument);
      }
    }
  }

}

TEST_F(FieldContainerTest, WriteHDF5) {

  FieldContainer fields(grid);

  auto scalar_mf = fields.AddField("cell_scalar_field", FieldLocation::CellCentered, 1, 1);
  auto vector_mf = fields.AddField("cell_vector_field", FieldLocation::CellCentered, 3, 1);

  const std::string filename = "Test_Output_FieldContainer_WriteHDF5.h5";
  const hid_t file_id = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
  fields.WriteHDF5(file_id);
  H5Fclose(file_id);

}
