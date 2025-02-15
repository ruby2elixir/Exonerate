defmodule ExonerateTest.Tutorial.ObjectTest do
  use ExUnit.Case, async: true

  @moduletag :object
  @moduletag :tutorial

  @moduledoc """
  basic tests from:

  https://json-schema.org/understanding-json-schema/reference/object.html
  Literally conforms to all the tests presented in this document.
  """

  defmodule Object do

    @moduledoc """
    tests from:

    https://json-schema.org/understanding-json-schema/reference/object.html#object

    """
    require Exonerate

    Exonerate.function_from_string(:def, :object, ~s({ "type": "object" }))
  end

  describe "basic objects example" do
    test "various objects match correctly" do
      assert :ok =
      """
      {
        "key"         : "value",
        "another_key" : "another_value"
      }
      """
      |> Jason.decode!
      |> Object.object

      assert :ok =
      """
      {
          "Sun"     : 1.9891e30,
          "Jupiter" : 1.8986e27,
          "Saturn"  : 5.6846e26,
          "Neptune" : 10.243e25,
          "Uranus"  : 8.6810e25,
          "Earth"   : 5.9736e24,
          "Venus"   : 4.8685e24,
          "Mars"    : 6.4185e23,
          "Mercury" : 3.3022e23,
          "Moon"    : 7.349e22,
          "Pluto"   : 1.25e22
      }
      """
      |> Jason.decode!
      |> Object.object
    end

    @badarray ["An", "array", "not", "an", "object"]

    test "objects mismatches a string or array" do
      assert {:error, list} = Object.object("Not an object")

      assert list[:schema_pointer] == "/type"
      assert list[:error_value] == "Not an object"
      assert list[:json_pointer] == "/"

      assert {:error, list} = Object.object(@badarray)

      assert list[:schema_pointer] == "/type"
      assert list[:error_value] == @badarray
      assert list[:json_pointer] == "/"
    end
  end

  defmodule Properties do

    @moduledoc """
    tests from:

    https://json-schema.org/understanding-json-schema/reference/object.html#properties

    """
    require Exonerate

    Exonerate.function_from_string(:def, :address1,
    """
    {
      "type": "object",
      "properties": {
        "number":      { "type": "number" },
        "street_name": { "type": "string" },
        "street_type": { "type": "string",
                         "enum": ["Street", "Avenue", "Boulevard"]
                       }
      }
    }
    """)

    Exonerate.function_from_string(:def, :address2,
    """
    {
      "type": "object",
      "properties": {
        "number":      { "type": "number" },
        "street_name": { "type": "string" },
        "street_type": { "type": "string",
                         "enum": ["Street", "Avenue", "Boulevard"]
                       }
      },
      "additionalProperties": false
    }
    """)

    Exonerate.function_from_string(:def, :address3,
    """
    {
      "type": "object",
      "properties": {
        "number":      { "type": "number" },
        "street_name": { "type": "string" },
        "street_type": { "type": "string",
                         "enum": ["Street", "Avenue", "Boulevard"]
                       }
      },
      "additionalProperties": { "type": "string" }
    }
    """)
  end

  @addr1 ~s({ "number": 1600, "street_name": "Pennsylvania", "street_type": "Avenue" })
  @addr2 ~s({ "number": "1600", "street_name": "Pennsylvania", "street_type": "Avenue" })
  @addr3 ~s({ "number": 1600, "street_name": "Pennsylvania" })
  @addr4 ~s({ "number": 1600, "street_name": "Pennsylvania", "street_type": "Avenue", "direction": "NW" })
  @addr5 ~s({ "number": 1600, "street_name": "Pennsylvania", "street_type": "Avenue", "office_number": 201 })

  describe "matching simple addresses" do
    test "explicit addresses match correctly" do
      assert :ok = @addr1
      |> Jason.decode!
      |> Properties.address1
    end

    test "deficient properties match correctly" do
      assert :ok = @addr3
      |> Jason.decode!
      |> Properties.address1
    end

    test "empty object matches correctly" do
      assert :ok = Properties.address1(%{})
    end

    test "extra properties matches correctly" do
      assert :ok = @addr4
      |> Jason.decode!
      |> Properties.address1
    end

    test "mismatched inner property doesn't match" do
      assert {:error, list} =
        @addr2
        |> Jason.decode!
        |> Properties.address1

      assert list[:schema_pointer] == "/properties/number/type"
      assert list[:error_value] == "1600"
      assert list[:json_pointer] == "/number"
    end
  end

  describe "matching addresses with additionalProperties forbidden" do
    test "explicit addresses match correctly" do
      assert :ok = @addr1
      |> Jason.decode!
      |> Properties.address2
    end

    test "extra properties matches correctly" do
      addr4 = Jason.decode!(@addr4)
      assert {:error, list} = Properties.address2(addr4)

      assert list[:schema_pointer] == "/additionalProperties"
      assert list[:error_value] == {"direction", "NW"}
      assert list[:json_pointer] == "/"
    end
  end

  describe "matching addresses with additionalProperties as an object" do
    test "explicit addresses match correctly" do
      assert :ok = @addr1
      |> Jason.decode!
      |> Properties.address3
    end

    test "matching additionalProperties matches correctly" do
      assert :ok = @addr4
      |> Jason.decode!
      |> Properties.address3
    end

    test "extra nonstring property doesn't match" do
      addr5 = Jason.decode!(@addr5)
      assert {:error, list} = Properties.address3(addr5)

      assert list[:schema_pointer] == "/additionalProperties/type"
      assert list[:error_value] == 201
      assert list[:json_pointer] == "/office_number"
    end
  end

  defmodule RequiredProperties do

    @moduledoc """
    tests from:

    https://json-schema.org/understanding-json-schema/reference/object.html#required-properties

    """
    require Exonerate

    Exonerate.function_from_string(:def, :contactinfo,
    """
    {
      "type": "object",
      "properties": {
        "name":      { "type": "string" },
        "email":     { "type": "string" },
        "address":   { "type": "string" },
        "telephone": { "type": "string" }
      },
      "required": ["name", "email"]
    }
    """)
  end

  @contact1 """
  {
    "name": "William Shakespeare",
    "email": "bill@stratford-upon-avon.co.uk"
  }
  """
  @contact2 """
  {
    "name": "William Shakespeare",
    "email": "bill@stratford-upon-avon.co.uk",
    "address": "Henley Street, Stratford-upon-Avon, Warwickshire, England",
    "authorship": "in question"
  }
  """
  @contact3 """
  {
    "name": "William Shakespeare",
    "address": "Henley Street, Stratford-upon-Avon, Warwickshire, England"
  }
  """

  describe "matching required properties" do
    test "basic contact matches correctly" do
      assert :ok = @contact1
      |> Jason.decode!
      |> RequiredProperties.contactinfo
    end

    test "extra info doesn't invalidate match" do
      assert :ok = @contact2
      |> Jason.decode!
      |> RequiredProperties.contactinfo
    end

    test "deficient info is a problem" do
      contact3 = Jason.decode!(@contact3)
      assert {:error, list} = RequiredProperties.contactinfo(contact3)

      assert list[:schema_pointer] == "/required/1"
      assert list[:error_value] == contact3
      assert list[:json_pointer] == "/"
    end
  end

  defmodule PropertyNames do

    @moduledoc """
    tests from:

    https://json-schema.org/understanding-json-schema/reference/object.html#property-names

    """
    require Exonerate

    Exonerate.function_from_string(:def, :token,
    """
    {
      "type": "object",
      "propertyNames": {
       "pattern": "^[A-Za-z_][A-Za-z0-9_]*$"
      }
    }
    """)
  end

  @token1 ~s({ "_a_proper_token_001": "value" })
  @token2 ~s({ "001 invalid": "value" })

  describe "matching property names" do
    test "basic contact matches correctly" do
      assert :ok = @token1
      |> Jason.decode!
      |> PropertyNames.token
    end

    test "not matching the property name doesn't match" do
      token2 = Jason.decode!(@token2)
      assert {:error, list} = PropertyNames.token(token2)

      assert list[:schema_pointer] == "/propertyNames/pattern"
      assert list[:error_value] == "001 invalid"
      assert list[:json_pointer] == "/001 invalid"
    end
  end

  defmodule Size do

    @moduledoc """
    tests from:

    https://json-schema.org/understanding-json-schema/reference/object.html#size

    """
    require Exonerate

    Exonerate.function_from_string(:def, :object,
    """
    {
      "type": "object",
      "minProperties": 2,
      "maxProperties": 3
    }
    """)
  end

  @objsize1 ~s({})
  @objsize2 ~s({ "a": 0 })
  @objsize3 ~s({ "a": 0, "b": 1 })
  @objsize4 ~s({ "a": 0, "b": 1, "c": 2 })
  @objsize5 ~s({ "a": 0, "b": 1, "c": 2, "d": 3 })

  describe "matching property size" do
    test "empty object mismatches" do
      objsize1 = Jason.decode!(@objsize1)
      assert {:error, list} = Size.object(objsize1)

      assert list[:schema_pointer] == "/minProperties"
      assert list[:error_value] == objsize1
      assert list[:json_pointer] == "/"
    end

    test "too small object mismatches" do
      objsize2 = Jason.decode!(@objsize2)
      assert {:error, list} = Size.object(objsize2)

      assert list[:schema_pointer] == "/minProperties"
      assert list[:error_value] == objsize2
      assert list[:json_pointer] == "/"
    end

    test "small goldilocks matches correctly" do
      assert :ok = @objsize3
      |> Jason.decode!
      |> Size.object
    end

    test "big goldilocks matches correctly" do
      assert :ok = @objsize4
      |> Jason.decode!
      |> Size.object
    end

    test "too large object mismatches" do
      objsize5 = Jason.decode!(@objsize5)
      assert {:error, list} = Size.object(objsize5)

      assert list[:schema_pointer] == "/maxProperties"
      assert list[:error_value] == objsize5
      assert list[:json_pointer] == "/"
    end
  end

  defmodule PatternProperties do

    @moduledoc """
    tests from:

    https://json-schema.org/understanding-json-schema/reference/object.html#pattern-properties

    """
    require Exonerate

    Exonerate.function_from_string(:def, :patternprop1,
    """
    {
      "type": "object",
      "patternProperties": {
        "^S_": { "type": "string" },
        "^I_": { "type": "integer" }
      },
      "additionalProperties": false
    }
    """)
  end

  @patternmatch1 ~s({ "S_25": "This is a string" })
  @patternmatch2 ~s({ "I_0": 42 })
  @patternmatch3 ~s({ "S_0": 42 })
  @patternmatch4 ~s({ "I_42": "This is a string" })
  @patternmatch5 ~s({ "keyword": "value" })

  describe "matching pattern properties without additionals" do
    test "string pattern works" do
      assert :ok = @patternmatch1
      |> Jason.decode!
      |> PatternProperties.patternprop1
    end

    test "integer pattern works" do
      assert :ok = @patternmatch2
      |> Jason.decode!
      |> PatternProperties.patternprop1
    end

    test "integers shouldn't match string pattern" do
      patternmatch3 = Jason.decode!(@patternmatch3)
      assert {:error, list} = PatternProperties.patternprop1(patternmatch3)

      assert list[:schema_pointer] == "/patternProperties/%5ES_/type"
      assert list[:error_value] == 42
      assert list[:json_pointer] == "/S_0"
    end

    test "strings shouldn't match integer pattern" do
      patternmatch4 = Jason.decode!(@patternmatch4)
      assert {:error, list} = PatternProperties.patternprop1(patternmatch4)

      assert list[:schema_pointer] == "/patternProperties/%5EI_/type"
      assert list[:error_value] == "This is a string"
      assert list[:json_pointer] == "/I_42"
    end

    test "additional properties shouldn't match" do
      patternmatch5 = Jason.decode!(@patternmatch5)
      assert {:error, list} = PatternProperties.patternprop1(patternmatch5)

      assert list[:schema_pointer] == "/additionalProperties"
      assert list[:error_value] == {"keyword", "value"}
      assert list[:json_pointer] == "/"
    end
  end
end
